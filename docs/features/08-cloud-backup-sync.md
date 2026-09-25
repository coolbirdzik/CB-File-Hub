# Cloud Backup & Sync

**Purpose**: Push the CB File Hub backup archive (settings + tags) to a user's own cloud drive — Google Drive, Dropbox or OneDrive — and restore it back on another machine.

The screen lives at the `#backup-sync` system path and is reached from Settings → Backup & Sync, so it renders inside the current tab like every other system screen.

## Layout

```
lib/services/backup/
├── backup_archive_service.dart      # builds/reads the .zip (unchanged)
├── cloud_backup_service.dart        # zip ⇄ provider orchestration + temp cleanup
└── cloud/
    ├── cloud_backup_provider.dart   # CloudBackupProvider interface + models
    ├── cloud_backup_registry.dart   # provider list, selected target
    ├── cloud_oauth_config.dart      # compile-time client ids
    ├── oauth_token_store.dart       # tokens in flutter_secure_storage
    ├── pkce_oauth_client.dart       # authorization code + PKCE, loopback redirect
    ├── oauth_cloud_provider.dart    # shared sign-in / refresh / authorized request
    ├── google_mobile_auth.dart      # Android/iOS sign-in through the Google SDK
    ├── google_drive_backup_provider.dart
    ├── dropbox_backup_provider.dart
    └── onedrive_backup_provider.dart
```

Every archive is stored in a folder named **CB File Hub Backups** on the remote drive, with a timestamped file name (`cb_file_hub_backup_20260921_143000.zip`), so old versions are kept rather than overwritten.

## Sign-in flow

All three providers use the same public-client flow (RFC 8252):

1. The app binds an `HttpServer` on `127.0.0.1`, preferring port **53682** (falling back to 53683/53684, then a random port for providers that allow it).
2. `url_launcher` opens the provider's consent page in the system browser with a PKCE `code_challenge`.
3. The browser redirects back to the loopback server, which answers with a small "you can close this tab" page.
4. The code is exchanged for tokens, which are written to the OS keychain via `flutter_secure_storage`.

Access tokens are refreshed automatically when they expire, and any request that still comes back `401` is retried once with a freshly refreshed token.

Dropbox validates the redirect URI verbatim, so it never falls back to a random port — if 53682-53684 are all taken, sign-in reports the conflict instead of failing obscurely.

### Google Drive on Android and iOS

Google deprecated the loopback redirect for mobile client types and no longer accepts custom URI schemes there either, so mobile cannot use the flow above. `GoogleDriveBackupProvider` therefore swaps its three entry points (`connect`, `accessToken`, `disconnect`) for `GoogleMobileAuth`, which wraps `google_sign_in` — Credential Manager on Android, the Google Sign-In SDK on iOS. The upload, download and listing code is shared with desktop.

The SDK hands out short-lived access tokens and keeps no refresh token of its own, so:

- every call asks the SDK for the current token (`authorizationForScopes`) instead of caching one;
- a `401` clears the rejected token (`clearAuthorizationToken`) before asking again, otherwise the SDK returns the same dead token;
- only the keychain entry that remembers *who* is signed in is written by the app; the tokens stay inside the SDK.

Authentication and authorization are separate steps on mobile: `authenticate()` identifies the user (and yields name/email for the UI), then `authorizeScopes(['drive.file'])` asks for the Drive grant. Both must happen from a user gesture, which the Connect button satisfies.

Dropbox and OneDrive still use the loopback flow on every platform, so on mobile they remain untested; local folder mode is the supported path for them there.

## Registering the OAuth clients

Client ids are compiled in, never committed. Build with:

```bash
flutter build windows \
  --dart-define=GOOGLE_DRIVE_CLIENT_ID=<id>.apps.googleusercontent.com \
  --dart-define=GOOGLE_DRIVE_CLIENT_SECRET=<secret> \
  --dart-define=DROPBOX_APP_KEY=<key> \
  --dart-define=ONEDRIVE_CLIENT_ID=<guid>
```

### Where the ids come from locally

Copy `.env.example` to `.env` in the repo root and fill in what you have. `.env` is git-ignored, and every local build path reads it:

- `scripts/build.sh` loads it into the environment (real environment variables still win, so CI secrets are never overridden);
- the `just` recipes that call flutter directly (`just windows`, `just android`, `just run`, ...) pass `--dart-define-from-file`;
- a bare flutter command can do the same: `flutter run -d windows --dart-define-from-file=../.env` from `cb_file_manager/`.

Keys that are absent or empty simply leave that provider unavailable.

`scripts/build.sh` picks the same names up from the environment and adds the `--dart-define` flags to every `flutter build` it runs (including the rebuild `msix:create` does), so exporting them by hand also works:

```bash
export GOOGLE_DRIVE_CLIENT_ID=... DROPBOX_APP_KEY=... ONEDRIVE_CLIENT_ID=...
./scripts/build.sh windows-portable
```

Android needs one more define, because it authenticates against a different client of the same project:

```bash
flutter build apk --dart-define=GOOGLE_DRIVE_SERVER_CLIENT_ID=<web client id>
```

That is the **web** client id, which is what Credential Manager authenticates against; the Android client itself is matched by package name + signing certificate and so never appears in the code. Without it, Google Drive is greyed out on Android.

iOS needs no define: the Google Sign-In SDK reads `GIDClientID` from `Info.plist`.

In GitHub Actions, add them as repository secrets (**Settings → Secrets and variables → Actions**) with exactly these names: `GOOGLE_DRIVE_CLIENT_ID`, `GOOGLE_DRIVE_CLIENT_SECRET`, `GOOGLE_DRIVE_SERVER_CLIENT_ID`, `DROPBOX_APP_KEY`, `ONEDRIVE_CLIENT_ID`. `release.yml` and `build-test.yml` map them to workflow-level env vars; the jobs that call `build.sh` inherit them, and the direct `flutter build apk/appbundle/windows` steps pass them explicitly. A missing secret just builds that provider as unavailable.

A provider whose id is missing shows up greyed out in the picker with "not available in this build".

| Provider | Console | Client type | Redirect URI | Scopes |
|----------|---------|-------------|--------------|--------|
| Google Drive (Windows/macOS/Linux) | Google Cloud Console → Credentials | **Desktop app** | loopback (any port, no registration needed) | `drive.file`, `openid`, `email` |
| Google Drive (Android) | Google Cloud Console → Credentials | **Android** + a **Web application** client | none (SDK flow) | `drive.file` |
| Google Drive (iOS) | Google Cloud Console → Credentials | **iOS** | none (SDK flow, id read from `Info.plist`) | `drive.file` |
| Dropbox | Dropbox App Console → scoped app | — | `http://127.0.0.1:53682`, `http://127.0.0.1:53683`, `http://127.0.0.1:53684` | `files.content.write`, `files.content.read`, `account_info.read` |
| OneDrive | Entra ID → App registrations | **Mobile and desktop applications** | `http://127.0.0.1` (port is ignored for loopback) | `Files.ReadWrite`, `User.Read`, `offline_access` |

Notes:

- The app always sends `127.0.0.1`, never `localhost`. Entra ID treats the two as different URIs, so a registration of `http://localhost` fails with `AADSTS50011`. If the portal's redirect URI box refuses `http://127.0.0.1`, add it to `replyUrlsWithType` in the app manifest instead.
- The Google client *secret* is needed on desktop even though Google's installed-app reference marks `client_secret` as optional: a "Desktop app" client answers `400 client_secret is missing` without it, on the code grant and on refresh. It is not confidential — it ships in the binary — and PKCE is what protects the flow. Dropbox, OneDrive and Google-on-Android have no secret at all.
- `drive.file` only grants access to files the app itself created, so the rest of the user's Drive stays invisible to CB File Hub. Google classifies it as non-sensitive, but a public app may still need basic OAuth app or brand verification. An External app in Testing only admits accounts listed under Google Auth Platform → Audience → Test users.
- Dropbox issues short-lived tokens; `token_access_type=offline` in the authorize request is what makes it return a refresh token.
- Microsoft only returns a refresh token when `offline_access` is among the scopes.

### Dev and prod registrations

One Google Cloud project can serve both, as long as every signing identity is registered. What must exist per platform:

| What | Dev build | Prod build |
|------|-----------|------------|
| Desktop client (Windows/macOS/Linux) | same "Desktop app" client works for both | same client |
| Android client | package `com.cbv.filehub` + SHA-1 of the **debug** keystore | package + SHA-1 of the **upload** key *and* of the Play App Signing key |
| Web client (`GOOGLE_DRIVE_SERVER_CLIENT_ID`) | one client, shared by dev and prod | same client |
| iOS client | only if iOS is shipped; configured through `Info.plist`, not a define | same |
| Consent screen | may stay in *Testing* with the developers as test users | must be **In production**, otherwise refresh tokens die after 7 days |

If Google shows **"Access blocked: CB FileHub has not completed the Google verification process"** during development, open the same Google Cloud project that owns the OAuth client ID compiled into the app, then add the exact Google Account used for sign-in under **Google Auth Platform → Audience → Test users**. Save and retry sign-in. For public use, configure the consent screen for production and complete any verification Google requests. Adding a test user fixes access while Testing; it does not publish or verify the app.

Getting the SHA-1 fingerprints:

```bash
# debug keystore (every developer machine has its own)
keytool -list -v -alias androiddebugkey -keystore ~/.android/debug.keystore -storepass android -keypass android

# upload key used by CI
keytool -list -v -alias "$ANDROID_KEY_ALIAS" -keystore upload-keystore.jks
```

The Play App Signing SHA-1 is different from the upload key and is shown in **Play Console → Release → Setup → App signing**. It only exists after the first upload, so Google sign-in in a Play-distributed build fails until that fingerprint is added as well.

Each developer's debug SHA-1 has to be added to the Android client, so a shared dev client needs one entry per machine.

## Local folder mode

The original behaviour is kept as a fourth option in the picker: write `cb_file_hub_cloud_backup.zip` into any folder, typically one already mirrored by Drive for Desktop / OneDrive / Dropbox. It needs no OAuth client and works on every platform.

## Limits and known gaps

- Uploads and downloads buffer the archive in memory. That is fine for settings + tags (a few MB); it is not a general file-sync path.
- Google uses a resumable upload session, so it is not bound by the 5 MB multipart cap; Dropbox (150 MB) and Graph (250 MB) use simple uploads.
- The loopback listener needs a browser on the same device, which is fine on desktop. Google Drive avoids it entirely on mobile (see above); Dropbox and OneDrive do not, so their mobile sign-in is untested and local folder mode remains the supported path there.
- macOS needs `com.apple.security.network.client`, `com.apple.security.network.server` and `keychain-access-groups` in both entitlement files, or the sandbox blocks the API calls, the loopback listener and the token store respectively.
- There is no automatic/scheduled sync yet: backup and restore are both explicit actions.
