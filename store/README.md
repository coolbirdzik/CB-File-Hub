# Shared app descriptions

Microsoft Store and Google Play use one description per language:

| Language | Description and feature bullets | Short description and locale |
|---|---|---|
| English | [listings/en-us.txt](listings/en-us.txt) | [listings/en-us.json](listings/en-us.json) |
| Vietnamese | [listings/vi-vn.txt](listings/vi-vn.txt) | [listings/vi-vn.json](listings/vi-vn.json) |

Edit the `.txt` files to describe new features. Keep the introduction brief and
use one `- ` bullet per feature group. Microsoft Store's feature list comes from
these bullets; Google Play's full description uses the same complete text.
The `.json` files contain the short description, text filename and Play language
code (`en-US` / `vi`). Microsoft locales remain `en-us` / `vi-vn`.

The validator enforces:

- Full description: 1–4,000 characters, shared by both stores.
- Short description: 1–80 characters, used by Google Play.
- Feature bullets: 1–20, each at most 200 characters, used by Microsoft Store.

The checked-in copy is about 1,400 characters per language. Describe what users
can do in plain language and mark features limited to desktop or Windows.
Do not paste the full README into a listing.

Limits and payloads follow [Google Play's listing guidance](https://support.google.com/googleplay/android-developer/answer/9859152?hl=en),
the [Play listing API](https://developers.google.com/android-publisher/api-ref/rest/v3/edits.listings/update)
and the [Microsoft submission API](https://learn.microsoft.com/en-us/windows/uwp/monetize/manage-app-submissions).

## Preview and checks

Run from the repository root; no credentials or network are needed:

```bash
node scripts/store_listings.mjs
node --test scripts/tests/store_listings.test.mjs scripts/tests/google_play_listings.test.mjs
```

CI checks this on pushes and pull requests. The release workflow also uploads
`store-listings-en-vi`, a JSON preview for both stores, before their build jobs.

## Release integration

- MSIX: `partner_center_msix.mjs submit` updates English/Vietnamese descriptions
  and features in the package submission. Existing metadata and image assets stay
  in place. See the [Microsoft Store guide](../docs/guides/02-microsoft-store-submission-guide.md).
- AAB: `google_play_listings.mjs prepare` creates one edit and updates both Play
  descriptions. The upload action receives `existingEditId`, adds the bundle and
  commits the combined release. Failed listing updates or uploads discard the
  uncommitted edit. `internalsharing` uploads skip listing updates.

Google Play uses the existing `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` and
`GOOGLE_PLAY_PACKAGE_NAME` configuration. The service account must be allowed to
manage the app's store presence as well as release bundles. An initial listing
with a product title must exist. Existing localized titles and videos are
preserved; a new Vietnamese listing takes the existing product title. Images,
contact details, release notes and unrelated locales are not replaced.

`STORE_LISTINGS_DIR` selects another directory for the Google Play script;
`PARTNER_CENTER_LISTINGS_DIR` does the same for Microsoft. CI uses `store/listings`.
For manual cleanup of an uncommitted Play edit, set `GOOGLE_PLAY_EDIT_ID` and run
`node scripts/google_play_listings.mjs discard` with the same account/package.
The preparation script itself never commits an edit.
