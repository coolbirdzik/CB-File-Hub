# macOS code signing

The macOS DMG is signed with a self-signed certificate named
`CB File Hub Signing`. It is not a Developer ID and the app is not notarized, so
users still allow the app once via System Settings > Privacy & Security >
Open Anyway (see `installer/macos/README.txt`).

## Why the certificate must never change

macOS privacy permissions (Full Disk Access, Files & Folders, Photos...) are
stored against the app's *designated requirement*:

- Ad-hoc signature (`codesign --sign -`): `cdhash H"..."`, the hash of that one
  build. Every update looked like a different app and lost all permissions.
- Certificate signature: `identifier "..." and certificate leaf = H"..."`. It
  is the same for every build signed with the same certificate, so permissions
  survive updates, including the in-app updater's bundle replacement
  (`lib/services/app_update/desktop_update_installer.dart`).

Replacing or losing the certificate resets every user's permissions once more.
Keep the exported `.p12` and its password in a password manager.

Check an installed build with:

```bash
codesign -d -r- "/Applications/CB File Hub.app"
```

## Where it is used

- `scripts/build.sh` (`resolve_macos_sign_identity`, `sign_macos_app`) signs
  with the certificate when it is in the keychain, otherwise ad-hoc with a
  warning. `MACOS_SIGN_IDENTITY` overrides the name;
  `MACOS_REQUIRE_SIGN_IDENTITY=1` turns a missing certificate into an error.
- `.github/workflows/release.yml` (`build-macos`) imports it into a temporary
  keychain from two secrets and requires it:
  - `MACOS_CERT_BASE64`: `base64 -i cb-signing.p12`
  - `MACOS_CERT_PASSWORD`: the `.p12` export password

- Local `flutter run` / `flutter build macos` builds use it when
  `macos/Runner/Configs/Signing.local.xcconfig` (git-ignored, copy of the
  `.example` next to it) exists. Dev builds then share the release app's
  identity, so one Full Disk Access grant covers both. Without the file they
  are ad-hoc signed and lose permissions on every rebuild. The Runner target
  does not set `CODE_SIGN_STYLE` itself so that this file can switch it to
  Manual.

## Dev runs: `just macos-dev`, not `flutter run`

`flutter run -d macos` starts the app as a child of the terminal, so macOS
checks privacy permissions against that "responsible" process (VS Code,
Terminal), not CB File Hub; granting Full Disk Access to CB File Hub does not
reach the dev build. `just macos-dev` (`scripts/macos_dev.sh`) builds the debug
app, launches it with `open` so it is responsible for itself, and runs
`flutter attach` for hot reload. App logs go to
`cb_file_manager/build/macos/dev_app.log`.

The installed app and the dev build share one permission entry
(`com.cb.cbFileManager`). If one of them is still ad-hoc signed (a release from
before this certificate), each grant replaces the other's and they keep losing
access; install a certificate-signed release.

No hardened runtime: without a Team ID, library validation would refuse the
bundled frameworks.

## Creating the certificate (one time only)

1. Keychain Access > Certificate Assistant > Create a Certificate...
2. Name `CB File Hub Signing`, Identity Type *Self Signed Root*, Certificate
   Type *Code Signing*, tick *Let me override defaults*, validity `7300` days,
   keep the other defaults, store it in the *login* keychain.
3. `security find-identity -p codesigning` lists it (as
   `CSSMERR_TP_NOT_TRUSTED`, which is expected and does not affect signing).
4. In *My Certificates*, right-click it > Export > `.p12` with a password, then
   set the two secrets:

```bash
base64 -i cb-signing.p12 | gh secret set MACOS_CERT_BASE64
gh secret set MACOS_CERT_PASSWORD
```
