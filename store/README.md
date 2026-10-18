# Shared app listings

Microsoft Store and Google Play use one description per app language:

| Language | Description and feature bullets | Short description, locale and Store images |
|---|---|---|
| English | [listings/en-us.txt](listings/en-us.txt) | [listings/en-us.json](listings/en-us.json) |
| Vietnamese | [listings/vi-vn.txt](listings/vi-vn.txt) | [listings/vi-vn.json](listings/vi-vn.json) |
| Turkish | [listings/tr-tr.txt](listings/tr-tr.txt) | [listings/tr-tr.json](listings/tr-tr.json) |
| Simplified Chinese | [listings/zh-cn.txt](listings/zh-cn.txt) | [listings/zh-cn.json](listings/zh-cn.json) |

These match the app's UI languages and the MSIX manifest
(`msix_config.languages` in `cb_file_manager/pubspec.yaml`); a test fails if
they drift apart. To add a language, add its `.txt`/`.json`, its promo images,
the locale to `requiredStoreLocales` in `scripts/store_listings.mjs` and to
`msix_config.languages`.

Edit the `.txt` files to describe new features. Keep the introduction brief and
use one `- ` bullet per feature group. Microsoft Store's feature list comes from
these bullets; Google Play's full description uses the same complete text.

Each `.json` file contains:

- `descriptionFile`: the sibling `.txt`.
- `shortDescription`: Google Play short description.
- `googlePlayLanguage`: Play language code (`en-US`, `vi`, `tr-TR`, `zh-CN`).
  Microsoft locales are the file names (`en-us`, `vi-vn`, `tr-tr`, `zh-cn`).
- `microsoftStoreImages`: ordered Microsoft Store images, each with `file`
  (PNG path relative to `store/listings/`), `imageType` and an optional
  `description` (screenshot caption).

The validator enforces:

- Full description: 1–4,000 characters, shared by both stores.
- Short description: 1–80 characters, used by Google Play.
- Feature bullets: 1–20, each at most 200 characters, used by Microsoft Store.
- Images: PNG, at most 50 MB, captions at most 200 characters, at least one
  `Screenshot`. Supported types: `Screenshot` (up to 10, 1366x768 to
  3840x2160), `PromotionalArt16x9` (16:9 super hero art, exactly 1920x1080 or
  3840x2160, no text) and `Icon` (300x300).

The checked-in copy is about 1,400 characters per language. Describe what users
can do in plain language and mark features limited to desktop or Windows.
Do not paste the full README into a listing.

Limits and payloads follow [Google Play's listing guidance](https://support.google.com/googleplay/android-developer/answer/9859152?hl=en),
the [Play listing API](https://developers.google.com/android-publisher/api-ref/rest/v3/edits.listings/update),
the [Microsoft submission API](https://learn.microsoft.com/en-us/windows/uwp/monetize/manage-app-submissions)
and [Microsoft Store image requirements](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/screenshots-and-images).

## Store images

Screenshots are the desktop promo images from `scripts/make_promo_images.py`
(`screenshots/promo/desktop/`, `vi/desktop/`, `tr/desktop/`, `zh/desktop/`),
captioned with each promo's subtitle. Each listing uses the Store maximum of 10:
file browser, gallery, torrent library (`11_*`, the qBittorrent import dialog
from `screenshots/features/torrents/`), three CB Agent scenes, tag assignment
(`12_*`), tag management, tag tree and disk cleaner. The album detail promo is
kept for the README but left out of the Store. Every language also uses the
text-free hero art `screenshots/promo/store/hero_16x9.png`. Regenerate with:

```bash
python scripts/make_promo_images.py --desktop-only            # all languages
python scripts/make_promo_images.py --desktop-only --languages tr,zh
```

## Preview and checks

Run from the repository root; no credentials or network are needed:

```bash
node scripts/store_listings.mjs
node --test scripts/tests/store_listings.test.mjs scripts/tests/google_play_listings.test.mjs
```

CI checks this on pushes and pull requests. The release workflow also uploads
`store-listings`, a JSON preview for both stores, before their build jobs.

## Release integration

- MSIX: `partner_center_msix.mjs submit` updates every language's description,
  features and images in the package submission, then waits for Partner Center
  to finish processing the commit (the job fails on `CommitFailed`). Titles,
  image types not listed in the `.json` (for example a manually uploaded
  `Icon`) and other metadata stay in place. See the
  [Microsoft Store guide](../docs/guides/02-microsoft-store-submission-guide.md).
- AAB: `google_play_listings.mjs prepare` creates one edit and updates every Play
  description. The upload action receives `existingEditId`, adds the bundle and
  commits the combined release. Failed listing updates or uploads discard the
  uncommitted edit. `internalsharing` uploads skip listing updates. Play
  graphics are not uploaded.

Google Play uses the existing `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` and
`GOOGLE_PLAY_PACKAGE_NAME` configuration. The service account must be allowed to
manage the app's store presence as well as release bundles. An initial listing
with a product title must exist. Existing localized titles and videos are
preserved; a new language listing takes the existing product title. Images,
contact details, release notes and unrelated locales are not replaced.

`STORE_LISTINGS_DIR` selects another directory for the Google Play script;
`PARTNER_CENTER_LISTINGS_DIR` does the same for Microsoft. CI uses `store/listings`.
For manual cleanup of an uncommitted Play edit, set `GOOGLE_PLAY_EDIT_ID` and run
`node scripts/google_play_listings.mjs discard` with the same account/package.
The preparation script itself never commits an edit.
