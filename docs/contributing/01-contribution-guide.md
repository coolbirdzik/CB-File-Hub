# Contribution Guide

- **Setup** Follow the [development setup](04-development-setup.md) for Flutter 3.47.2, workspace commands, and the Windows, macOS, Linux, or Android toolchain.
- **Branches** Work off feature branches (`feat/<topic>`). Never push directly to `main`.
- **Before PR** Run `flutter test`, fix lints, attach screenshots for UI changes.
- **Standards** Follow `docs/contributing/02-coding-standards.md` and theme/i18n rules in `docs/coding-rules/`.
- **Commits** Use Conventional Commit prefixes.
- **Reviews** Keep pull requests focused and reply quickly to comments.

## Local Pre-Push Checks

Run the same checks as CI from `cb_file_manager` before pushing:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

## Git Hook (pre-push)

Set up a local `pre-push` hook so these checks run automatically.

### Option A: Bash (macOS/Linux/Git Bash)

Create `.git/hooks/pre-push`:

```bash
#!/usr/bin/env bash
set -euo pipefail

cd cb_file_manager
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Then make it executable:

```bash
chmod +x .git/hooks/pre-push
```

### Option B: PowerShell (Windows)

Create `.git/hooks/pre-push` with:

```powershell
#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"

Set-Location cb_file_manager
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

If any command fails, push is blocked until the issue is fixed.
