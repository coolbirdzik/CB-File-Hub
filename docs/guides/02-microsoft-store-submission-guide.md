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

1. Validate the checked-in English/Vietnamese listing text and run mocked submission tests
2. Upload `store-listings-en-vi`, a shared JSON preview of the exact text for Microsoft Store and Google Play
3. Restore the `.pfx` from `MSIX_CERT_BASE64`, build and sign the Windows MSIX
4. Upload the `.msix` as the `windows-msix` artifact and prepare its submission archive
5. Update the Store draft's `en-us` and `vi-vn` descriptions/features and upload the package
6. Commit for certification with `targetPublishMode: Immediate`; Microsoft Store publishes automatically after approval

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

## 6. Maintain English and Vietnamese Descriptions

Microsoft Store and Google Play share these version-controlled descriptions:

| Language | Full description and feature bullets | Short description / locale metadata |
|---|---|---|
| English (`en-us`) | [`store/listings/en-us.txt`](../../store/listings/en-us.txt) | [`en-us.json`](../../store/listings/en-us.json) |
| Vietnamese (`vi-vn`) | [`store/listings/vi-vn.txt`](../../store/listings/vi-vn.txt) | [`vi-vn.json`](../../store/listings/vi-vn.json) |

Keep both languages concise and aligned. Lines beginning with `- ` generate
Microsoft Store's features automatically, so feature text is maintained once.
The `.json` files hold `descriptionFile`, `shortDescription` and
`googlePlayLanguage`; product capabilities and platform limits live in the `.txt`.

`scripts/store_listings.mjs` validates required locales, shared description length
(1–4,000 characters), short descriptions (1–80 characters), and feature bullets
(1–20 entries, at most 200 characters each). The shared limit fits
[Google Play](https://support.google.com/googleplay/android-developer/answer/9859152?hl=en)
and Microsoft Store. `scripts/partner_center_msix.mjs submit` validates the text before
authenticating or modifying a draft, then merges only `description` and `features`
into `listings[locale].baseListing`. The data shape follows the
[Microsoft Store submission API](https://learn.microsoft.com/en-us/windows/uwp/monetize/manage-app-submissions).

Existing titles, images, policy/support URLs, terms, release notes, platform
overrides and unrelated languages remain intact. If Vietnamese is new, its
listing is seeded from the existing English Store metadata before applying the
Vietnamese text. An initial Store listing with a registered title must already
exist. `PARTNER_CENTER_LISTINGS_DIR` can select another content directory; release
CI explicitly uses `store/listings`.

Preview and test locally from the repository root without Store credentials or
network requests:

```bash
node scripts/store_listings.mjs
node --test scripts/tests/store_listings.test.mjs scripts/tests/google_play_listings.test.mjs
```

PR/push CI validates the content. Release jobs wait for the same checks and
upload a `store-listings-en-vi` preview containing payloads for both stores.
Google Play's AAB job prepares an uncommitted edit with both descriptions and
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
of existing Store image assets, which this description update preserves.
