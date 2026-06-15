import fs from 'node:fs';
import path from 'node:path';

const TOKEN_RESOURCE = 'https://manage.devcenter.microsoft.com';
const API_ROOT = 'https://manage.devcenter.microsoft.com/v1.0/my';

function requiredEnv(name) {
  const value = process.env[name];
  if (!value || value.trim() === '') {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value.trim();
}

function optionalEnv(name) {
  const value = process.env[name];
  return value && value.trim() !== '' ? value.trim() : '';
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

async function getAccessToken() {
  const tenantId = requiredEnv('PARTNER_CENTER_TENANT_ID');
  const body = new URLSearchParams({
    grant_type: 'client_credentials',
    client_id: requiredEnv('PARTNER_CENTER_CLIENT_ID'),
    client_secret: requiredEnv('PARTNER_CENTER_CLIENT_SECRET'),
    resource: TOKEN_RESOURCE,
  });

  const response = await fetch(
    `https://login.microsoftonline.com/${encodeURIComponent(
      tenantId,
    )}/oauth2/token`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
      },
      body,
    },
  );
  const payload = await parseResponse(response);
  if (!response.ok) {
    throw new Error(`Partner Center token request failed: ${formatError(payload)}`);
  }
  if (!payload?.access_token) {
    throw new Error('Partner Center token response did not include access_token');
  }
  return payload.access_token;
}

async function apiRequest(accessToken, method, relativePath, body = undefined) {
  const response = await fetch(`${API_ROOT}${relativePath}`, {
    method,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      Accept: 'application/json',
      ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const payload = await parseResponse(response);
  if (!response.ok) {
    throw new Error(
      `Partner Center API ${method} ${relativePath} failed: ${formatError(
        payload,
      )}`,
    );
  }
  return payload;
}

async function createSubmission(accessToken, appId) {
  return apiRequest(
    accessToken,
    'POST',
    `/applications/${encodeURIComponent(appId)}/submissions`,
  );
}

async function deleteSubmission(accessToken, appId, submissionId) {
  return apiRequest(
    accessToken,
    'DELETE',
    `/applications/${encodeURIComponent(appId)}/submissions/${encodeURIComponent(
      submissionId,
    )}`,
  );
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function createSubmissionWithRetry(accessToken, appId) {
  const maxAttempts = 4;
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      return await createSubmission(accessToken, appId);
    } catch (error) {
      if (attempt === maxAttempts || !error.message.includes('Conflict')) {
        throw error;
      }
      await sleep(5000 * attempt);
    }
  }
  throw new Error('Failed to create Partner Center submission');
}

function submissionPath(appId, submissionRef) {
  if (!submissionRef?.id && !submissionRef?.resourceLocation) {
    return '';
  }
  if (submissionRef.resourceLocation) {
    return `/${submissionRef.resourceLocation.replace(/^\/+/, '')}`;
  }
  return `/applications/${encodeURIComponent(appId)}/submissions/${encodeURIComponent(
    submissionRef.id,
  )}`;
}

async function getSubmission(accessToken, appId, submissionRef) {
  const relativePath = submissionPath(appId, submissionRef);
  if (!relativePath) {
    return null;
  }
  return apiRequest(accessToken, 'GET', relativePath);
}

function parseMsixVersion(value) {
  if (typeof value !== 'string') {
    return null;
  }
  const parts = value.split('.').map((part) => Number.parseInt(part, 10));
  if (
    parts.length !== 4 ||
    parts.some((part) => !Number.isSafeInteger(part) || part < 0)
  ) {
    return null;
  }
  return parts;
}

function collectPackageVersions(submission) {
  const versions = [];
  for (const appPackage of submission?.applicationPackages || []) {
    const version = parseMsixVersion(appPackage.version);
    if (version) {
      versions.push(version);
    }
  }
  return versions;
}

async function collectStoreVersions(accessToken, appId) {
  const app = await apiRequest(
    accessToken,
    'GET',
    `/applications/${encodeURIComponent(appId)}`,
  );
  const submissions = await Promise.all([
    getSubmission(accessToken, appId, app.lastPublishedApplicationSubmission),
    getSubmission(accessToken, appId, app.pendingApplicationSubmission),
  ]);
  return submissions.flatMap(collectPackageVersions);
}

async function resolveVersion() {
  const versionName = requiredEnv('MSIX_VERSION_NAME');
  const versionParts = versionName
    .split('.')
    .map((part) => Number.parseInt(part, 10));
  if (
    versionParts.length !== 3 ||
    versionParts.some((part) => !Number.isSafeInteger(part) || part < 0)
  ) {
    throw new Error(`MSIX_VERSION_NAME must be x.y.z, got ${versionName}`);
  }

  const appId = requiredEnv('PARTNER_CENTER_APP_ID');
  const accessToken = await getAccessToken();
  const versions = await collectStoreVersions(accessToken, appId);
  const matchingBuildNumbers = versions
    .filter((version) =>
      versionParts.every((part, index) => version[index] === part),
    )
    .map((version) => version[3]);

  const currentStoreBuild =
    matchingBuildNumbers.length > 0 ? Math.max(...matchingBuildNumbers) : 0;
  const nextBuild =
    matchingBuildNumbers.length > 0 ? currentStoreBuild + 1 : currentStoreBuild;
  const resolvedVersion = `${versionParts.join('.')}.${nextBuild}`;

  console.error(
    `Partner Center package versions: ${
      versions.length > 0
        ? versions.map((version) => version.join('.')).join(', ')
        : '(none)'
    }`,
  );
  console.error(
    `Resolved MSIX version: ${versionParts.join('.')}.${nextBuild}`,
  );
  console.log(resolvedVersion);
}

function packageForDeletion(appPackage) {
  return {
    id: appPackage.id,
    fileName: appPackage.fileName,
    fileStatus: 'PendingDelete',
    minimumDirectXVersion: appPackage.minimumDirectXVersion || 'None',
    minimumSystemRam: appPackage.minimumSystemRam || 'None',
  };
}

async function uploadSubmissionArchive(sasUrl, archivePath) {
  const stat = await fs.promises.stat(archivePath);
  const body = fs.createReadStream(archivePath);
  const response = await fetch(sasUrl, {
    method: 'PUT',
    headers: {
      'Content-Type': 'application/zip',
      'Content-Length': String(stat.size),
      'x-ms-blob-type': 'BlockBlob',
    },
    body,
    duplex: 'half',
  });
  const payload = await parseResponse(response);
  if (!response.ok) {
    throw new Error(`Azure Blob package upload failed: ${formatError(payload)}`);
  }
}

async function submitPackage() {
  const appId = requiredEnv('PARTNER_CENTER_APP_ID');
  const archivePath = path.resolve(requiredEnv('PARTNER_CENTER_PACKAGE_ARCHIVE'));
  const packageFileName =
    optionalEnv('PARTNER_CENTER_PACKAGE_FILE_NAME') || path.basename(archivePath);

  if (!fs.existsSync(archivePath)) {
    throw new Error(`Package archive not found: ${archivePath}`);
  }

  const accessToken = await getAccessToken();
  const app = await apiRequest(
    accessToken,
    'GET',
    `/applications/${encodeURIComponent(appId)}`,
  );
  const pendingSubmission = await getSubmission(
    accessToken,
    appId,
    app.pendingApplicationSubmission,
  );
  let submissionOrigin = pendingSubmission
    ? 'existing pending'
    : 'newly created';
  let submission = pendingSubmission || (await createSubmission(accessToken, appId));

  if (!submission?.id) {
    throw new Error('Partner Center did not return a submission id');
  }
  if (!submission.fileUploadUrl) {
    const replacePending =
      optionalEnv('PARTNER_CENTER_REPLACE_PENDING_WITHOUT_UPLOAD_URL') !==
      'false';
    const canDeletePending = ['PendingCommit', 'CommitFailed'].includes(
      submission.status,
    );
    if (!pendingSubmission || !replacePending || !canDeletePending) {
      throw new Error(
        `Partner Center submission ${submission.id} did not include fileUploadUrl. Delete the pending submission in Partner Center and rerun, or set PARTNER_CENTER_REPLACE_PENDING_WITHOUT_UPLOAD_URL=true for a PendingCommit/CommitFailed draft.`,
      );
    }

    console.error(
      `Deleting pending Partner Center submission without fileUploadUrl: ${submission.id} (${submission.status})`,
    );
    try {
      await deleteSubmission(accessToken, appId, submission.id);
    } catch (error) {
      if (error.message.includes('created through the API')) {
        throw new Error(
          `Partner Center has an in-progress submission (${submission.id}) that was created outside the API. Delete or cancel that pending submission in Partner Center, then rerun this workflow so CI can create the next submission through the API.`,
        );
      }
      throw error;
    }
    submission = await createSubmissionWithRetry(accessToken, appId);
    submissionOrigin = 'replacement';
    if (!submission?.id) {
      throw new Error('Partner Center did not return a replacement submission id');
    }
    if (!submission.fileUploadUrl) {
      throw new Error(
        `Replacement Partner Center submission ${submission.id} did not include fileUploadUrl`,
      );
    }
  }
  console.error(
    submissionOrigin === 'existing pending'
      ? `Using existing pending Partner Center submission: ${submission.id}`
      : `Created ${submissionOrigin} Partner Center submission: ${submission.id}`,
  );

  const publishMode = optionalEnv('PARTNER_CENTER_TARGET_PUBLISH_MODE');
  if (publishMode) {
    submission.targetPublishMode = publishMode;
    if (publishMode !== 'SpecificDate') {
      submission.targetPublishDate = '1601-01-01T00:00:00Z';
    }
  }

  submission.applicationPackages = [
    ...(submission.applicationPackages || []).map(packageForDeletion),
    {
      fileName: packageFileName,
      fileStatus: 'PendingUpload',
      minimumDirectXVersion: 'None',
      minimumSystemRam: 'None',
    },
  ];

  await apiRequest(
    accessToken,
    'PUT',
    `/applications/${encodeURIComponent(appId)}/submissions/${encodeURIComponent(
      submission.id,
    )}`,
    submission,
  );
  await uploadSubmissionArchive(submission.fileUploadUrl, archivePath);
  if (optionalEnv('PARTNER_CENTER_COMMIT_SUBMISSION') === 'true') {
    await apiRequest(
      accessToken,
      'POST',
      `/applications/${encodeURIComponent(appId)}/submissions/${encodeURIComponent(
        submission.id,
      )}/commit`,
    );
    console.error(`Partner Center submission committed: ${submission.id}`);
  } else {
    console.error(
      `Partner Center draft prepared without commit: ${submission.id}`,
    );
  }

  console.log(submission.id);
}

const command = process.argv[2];
if (!['resolve-version', 'submit'].includes(command)) {
  console.error('Usage: node scripts/partner_center_msix.mjs <resolve-version|submit>');
  process.exit(2);
}

const action = command === 'resolve-version' ? resolveVersion : submitPackage;
action().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
