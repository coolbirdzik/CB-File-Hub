# Microsoft Store Submission Guide

## Required Store Identity

These values must match Microsoft Partner Center exactly:

| Field | Value |
|---|---|
| `Package/Identity/Name` | `CoolBirdZik.CBFileHub` |
| `Package/Identity/Publisher` | `CN=C193F601-16B4-4BC5-89D3-1AE882F628DE` |
| `Package/Properties/PublisherDisplayName` | `CoolBirdZik` |

They are configured in `cb_file_manager/pubspec.yaml`.

## 1. Prepare a Signing Certificate

You need a `.pfx` certificate whose **Subject** matches:

```text
CN=C193F601-16B4-4BC5-89D3-1AE882F628DE
```

For local testing, you can create one with PowerShell:

```powershell
$subject = "CN=C193F601-16B4-4BC5-89D3-1AE882F628DE"
$cert = New-SelfSignedCertificate -Type Custom -Subject $subject -CertStoreLocation "Cert:\CurrentUser\My" -KeyUsage DigitalSignature -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3")
$password = ConvertTo-SecureString "ReplaceWithStrongPassword" -AsPlainText -Force
Export-PfxCertificate -Cert $cert -FilePath "$PWD\cb-file-hub-signing.pfx" -Password $password
```

## 2. Add GitHub Secrets

Create these repository secrets:

- `MSIX_CERT_BASE64`
- `MSIX_CERT_PASSWORD`
- `MSIX_PUBLISHER`

Convert `.pfx` to base64:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes(".\cb-file-hub-signing.pfx")) | Set-Clipboard
```

Set:

- `MSIX_CERT_BASE64`: base64 string of the `.pfx`
- `MSIX_CERT_PASSWORD`: password of the `.pfx`
- `MSIX_PUBLISHER`: `CN=C193F601-16B4-4BC5-89D3-1AE882F628DE`

## 3. Build the Signed MSIX

Push a release tag or run the release workflow manually.

The pipeline will:

1. Validate the checked-in listing text and images (`en-us`, `vi-vn`, `tr-tr`, `zh-cn`) and run mocked submission tests
2. Upload `store-listings`, a shared JSON preview of the exact text and images for Microsoft Store and Google Play
3. Restore the `.pfx` from `MSIX_CERT_BASE64`, build and sign the Windows MSIX (its manifest declares the same four languages)
4. Upload the `.msix` as the `windows-msix` artifact
5. Update every listing's description, features, screenshots and hero art, then upload one ZIP with the package and any changed images
6. Commit for certification with `targetPublishMode: Immediate` and wait until Partner Center has processed the commit; the job fails on `CommitFailed` and prints Partner Center's errors/warnings
7. Microsoft Store publishes automatically after certification (this can take up to a few business days; the public listing keeps the old text and images until then)

The release workflow always sets `PARTNER_CENTER_COMMIT_SUBMISSION=true` and
`PARTNER_CENTER_TARGET_PUBLISH_MODE=Immediate`. Repository variables with those
names do not override release publishing.

The `.msix` is intentionally not attached to the GitHub Release: the certificate is
self-signed, so a direct install fails with `0x800B010A` on machines that don't trust it.
The Store re-signs the package on publish, so Store installs are unaffected.

## 4. Verify Before Submission

Check the built MSIX locally:

```powershell
Get-AuthenticodeSignature .\CBFileManager-1.0.0.msix | Format-List Status,SignerCertificate
(Get-AuthenticodeSignature .\CBFileManager-1.0.0.msix).SignerCertificate.Subject
```

Expected:

- `Status` is `Valid`
- `Subject` is `CN=C193F601-16B4-4BC5-89D3-1AE882F628DE`

`Status` is only `Valid` on a machine that trusts the certificate. Elsewhere it shows
`UnknownError` (the same `0x800B010A` chain error). To test-install locally, install the
certificate into **Local Machine > Trusted People** first.

## 5. Submit to Microsoft Store

Release builds submit automatically. Monitor certification and publication status
in Partner Center; a successful workflow means the submission was committed,
while Store approval and publication continue asynchronously.

For a local MSIX build submitted manually in Partner Center:

1. Open the app submission page
2. Upload the generated `.msix`
3. Confirm package identity matches Partner Center
4. Complete store listing fields
5. Submit for certification

## 6. Maintain Listing Text and Images

Microsoft Store and Google Play share these version-controlled listings, one per
app UI language:

| Language | Full description and feature bullets | Short description / locale / images |
|---|---|---|
| English (`en-us`) | [`store/listings/en-us.txt`](../../store/listings/en-us.txt) | [`en-us.json`](../../store/listings/en-us.json) |
| Vietnamese (`vi-vn`) | [`store/listings/vi-vn.txt`](../../store/listings/vi-vn.txt) | [`vi-vn.json`](../../store/listings/vi-vn.json) |
| Turkish (`tr-tr`) | [`store/listings/tr-tr.txt`](../../store/listings/tr-tr.txt) | [`tr-tr.json`](../../store/listings/tr-tr.json) |
| Simplified Chinese (`zh-cn`) | [`store/listings/zh-cn.txt`](../../store/listings/zh-cn.txt) | [`zh-cn.json`](../../store/listings/zh-cn.json) |

Keep all languages concise and aligned. Lines beginning with `- ` generate
Microsoft Store's features automatically, so feature text is maintained once.
The `.json` files hold `descriptionFile`, `shortDescription`,
`googlePlayLanguage` and `microsoftStoreImages`; product capabilities and
platform limits live in the `.txt`. The same locales are declared in the MSIX
manifest (`msix_config.languages`), so Partner Center lists them as supported
package languages; a test keeps both lists identical.

`scripts/store_listings.mjs` validates required locales, shared description length
(1–4,000 characters), short descriptions (1–80 characters), feature bullets
(1–20 entries, at most 200 characters each) and images (PNG type, dimensions per
image type, count, 50 MB, 200-character captions). `scripts/partner_center_msix.mjs submit`
validates everything before authenticating or modifying a draft, then merges
`description`, `features` and the managed `images` into
`listings[locale].baseListing`. The data shape follows the
[Microsoft Store submission API](https://learn.microsoft.com/en-us/windows/uwp/monetize/manage-app-submissions).

Images are managed per image type: for each type listed in a locale's
`microsoftStoreImages` (by default `Screenshot` and `PromotionalArt16x9`), the
existing images of that type are marked `PendingDelete` and the checked-in ones
are added as `PendingUpload`, in order. Uploaded file names contain a content
hash, so when Partner Center still reports the same files nothing is re-uploaded.
Image types not listed (for example a manually uploaded `Icon` or Xbox art) stay
untouched. Set `PARTNER_CENTER_UPDATE_IMAGES=false` to update only text.

Existing titles, policy/support URLs, terms, release notes, platform overrides
and unrelated languages remain intact. A new language listing is seeded from the
existing English Store metadata (without English images) before applying its
text and images. An initial Store listing with a registered title must already
exist. `PARTNER_CENTER_LISTINGS_DIR` can select another content directory; release
CI explicitly uses `store/listings`.

After the commit, the script polls the submission status
(`PARTNER_CENTER_COMMIT_POLL_SECONDS`, default 30;
`PARTNER_CENTER_COMMIT_TIMEOUT_SECONDS`, default 1800). `CommitFailed` fails the
job with Partner Center's error list; a timeout only emits a warning.

Preview and test locally from the repository root without Store credentials or
network requests:

```bash
node scripts/store_listings.mjs
node --test scripts/tests/store_listings.test.mjs scripts/tests/google_play_listings.test.mjs
```

PR/push CI validates the content. Release jobs wait for the same checks and
upload a `store-listings` preview containing payloads for both stores.
Google Play's AAB job prepares an uncommitted edit with every description and
passes its ID to `upload-google-play`; that action uploads the AAB and commits
the descriptions with the release. Failed updates/uploads discard the edit.
Internal app sharing skips listing updates because it has no store release edit.
See [shared content and Google Play setup](../../store/README.md).

The tests mock authentication and Store requests, including Microsoft package
upload/commit and Google Play edit preparation/cleanup. They do not contact either
store. Running real submission commands uses release credentials.

## 7. Torrent Screenshots for the README

Eight production-dialog renders (four scenes in each language) are checked in at
[`screenshots/features/torrents/`](../../screenshots/features/torrents/). They show
qBittorrent import, another client profile, clipboard magnet prefill and download
destination/start options, using sample paths and data.

Render them from `cb_file_manager/`:

```bash
flutter test --no-pub tool/capture_torrent_screenshots_test.dart --dart-define=CB_CAPTURE_SCREENSHOTS=true
```

This is an opt-in widget renderer. It does not launch the Windows app, scan user
data, contact trackers or download payloads. README screenshots are independent
of the Store images, which come from `screenshots/promo/` (see section 6).
