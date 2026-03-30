# Release Guide

## Version & Build Number System

The project uses **Semantic Versioning** with an auto-incrementing build number:

```
version: {major}.{minor}.{patch}+{build_number}
# Example: version: 1.2.3+5
```

- **`{major}.{minor}.{patch}`** — Version name, set manually before release.
- **`+{build_number}`** — Auto-incremented by CI on every build. Stored in `pubspec.yaml` and committed back to the repo.

This ensures every build (even the same tag pushed multiple times) gets a unique build number across all platforms.

---

## Quick Release (Recommended)

```bash
# 1. Create a patch/minor/major release
make release-patch   # bump x.x.{Y+1}
make release-minor  # bump x.{Y+1}.0
make release-major  # bump {X+1}.0.0

# 2. Push to trigger CI builds
git push origin main && git push origin v1.2.3
```

> **Note:** `make release-*` automatically runs `make verify` first (`dart format` + `flutter analyze`).
> If code checks fail, the release is blocked until fixed.

CI will automatically:
1. Validate the tag matches `pubspec.yaml` version.
2. Increment the build number (`+1`, `+2`, ...).
3. Commit the updated `pubspec.yaml` back to the repo.
4. Build release artifacts (Windows portable ZIP, Windows MSI, Windows MSIX, Android APK, Android AAB).
5. Create a GitHub Release with changelog and download links.

For Microsoft Store and MSIX signing details, see:

- `docs/guides/02-microsoft-store-submission-guide.md`

---

## Manual Build (Local or Custom CI)

### Check current version

```bash
make version        # shows: 1.2.3+5
make version-info   # shows version_name, build_number separately
```

### Verify code before commit

```bash
make verify          # dart format + flutter analyze
```

### Bump build number manually

```bash
make bump-build      # runs verify, bumps +5 → +6, commits to git
```

### Update version name (creates new release point)

```bash
make update-version NEW_VERSION=1.3.0   # sets 1.3.0+1
make release-patch                        # then tag & push
```

### Build locally

```bash
make android        # Android APK
make windows        # Windows portable
make linux          # Linux
make macos          # macOS (macOS only)
```

### Custom build with explicit version

```bash
# Set specific version/build
sed -i 's/version:.*/version: 1.2.3+7/' cb_file_manager/pubspec.yaml
make android
```

---

## How It Works

### CI Flow (`.github/workflows/release.yml`)

```
git push tag "v1.2.3"
    │
    ▼
generate-release-notes job:
    │
    ├─ Read pubspec: version: 1.2.3+5
    ├─ Validate tag "v1.2.3" == "v1.2.3" ✅
    ├─ NEW_BUILD = 5 + 1 = 6
    ├─ Update pubspec: version: 1.2.3+6
    ├─ git commit & push: "ci: auto bump build number to 6"
    │
    ▼
Build jobs receive:
    version_name  = "1.2.3"
    version_code  = 6
    │
    ├─ Android:  versionName=1.2.3, versionCode=6
    ├─ Windows:  --build-name=1.2.3, --build-number=6
    ├─ macOS:    CFBundleShortVersion=1.2.3, CFBundleVersion=6
    └─ Linux:    build-name=1.2.3, build-number=6
    │
    ▼
GitHub Release created with all artifacts
```

### Retagging Same Version

```bash
# Recreate annotated tag and force-push
bash scripts/retag.sh v1.2.3

# CI reads pubspec: version: 1.2.3+6
# CI bumps to: version: 1.2.3+7
# Build: versionCode=7 ✅
```

This is fully **repo-based** — no dependency on GitHub Run IDs, works with any git provider.

---

## Platform Artifacts

| Platform | Artifact | Notes |
|---|---|---|
| Android | `CBFileManager-{ver}-{arch}.apk` | arm64-v8a, armeabi-v7a, x86_64 |
| Android | `CBFileManager-{ver}.aab` | For Google Play |
| Windows | `CBFileManager-{ver}-windows-portable.zip` | No install needed |
| Windows | `CBFileManager-Setup-{ver}.msi` | Classic desktop installer |
| Windows | `CBFileManager-{ver}.msix` | Signed package for Store or enterprise |

---

## Retagging (Beta / Hotfix Builds)

For beta or hotfix scenarios where the version stays the same but you need multiple CI builds with incrementing build numbers:

```bash
# Specific version (recommended)
bash scripts/retag.sh v1.2.3

# Interactive (detects latest tag automatically)
make retag
```

Both recreate the annotated tag and force-push it. Each run increments the build number:
```
v1.2.3 push #1 → build_number: +2
v1.2.3 push #2 → build_number: +3
v1.2.3 push #3 → build_number: +4  (beta 3)
...
```

---

## Makefile Targets Reference

| Target | Description |
|---|---|
| `make version` | Show current full version |
| `make version-info` | Show version name + build number separately |
| `make verify` | Run `dart format` + `flutter analyze` |
| `make bump-build` | Run verify, increment build number, commit to git |
| `make update-version NEW_VERSION=x.y.z` | Set new version name (resets build_number to +1) |
| `make release-patch` | Run verify, bump patch, create tag, commit |
| `make release-minor` | Run verify, bump minor, create tag, commit |
| `make release-major` | Run verify, bump major, create tag, commit |
| `make retag` | Interactive — recreate & push annotated tag |
| `bash scripts/retag.sh v1.2.3` | Recreate annotated tag and force-push |

---

## Troubleshooting

### Tag mismatch error in CI

```
Tag v1.2.3 does not match pubspec version v1.2.4
```

The tag must match the version name in `pubspec.yaml`. Either:
- Update the tag: `git tag -a "v1.2.4" ... && git push -f origin v1.2.4`
- Update pubspec: `make update-version NEW_VERSION=1.2.3`

### Build number not incrementing

Ensure the CI job has write permission to commit back to the repo. The `release.yml` workflow uses `secrets.GITHUB_TOKEN` with default write permissions.

### Multiple CI runs for same tag

Each push of the same tag creates a new build with an incremented build number. This is intentional — allows hotfix rebuilds without version changes.
