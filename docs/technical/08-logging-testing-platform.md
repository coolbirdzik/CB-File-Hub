# Logging, Testing, and Platform Notes

## Logging

- `utils/app_logger.dart` is preferred for structured operational logging where
  severity, error objects, or stack traces matter.
- `print()`, `debugPrint()`, and existing targeted diagnostics are permitted by
  this repository's analyzer conventions. Do not perform broad logging rewrites
  unrelated to the task.
- Never log credentials, access tokens, private prompts, or unredacted sensitive
  paths.
- Example structured logging:

  ```dart
  import 'package:cb_file_manager/utils/app_logger.dart';

  AppLogger.info('Operation started');
  AppLogger.warning('Operation degraded', error: error);
  AppLogger.error('Operation failed', error: error, stackTrace: stackTrace);
  ```

Use the level that matches operational severity. Preserve the original error
and stack trace when they are available.

## Testing and tooling

- Run workspace recipes from the root with `just`; run direct Flutter/Dart
  commands from `cb_file_manager/`.
- CI order is format check, analyze, unit/widget tests, Windows E2E, then build.
- Desktop E2E uses `integration_test/` with `--dart-define=CB_E2E=true`.
- Focused commands by feature are listed in the
  [test-impact map](../agent/verification/test-impact-map.yaml).
- Automated checks do not prove perceived latency, native menu behavior, or
  other runtime UX. Report manual confirmation separately.
- A new `integration_test/*.dart` file is not run by CI or `just
  e2e-parallel` until it is wired into `tool/e2e_parallel.dart`, `justfile`
  (`e2e-list`), and `.github/workflows/build-test.yml`.
- E2E tests that pass locally but fail only on GitHub Actions CI are a known,
  recurring pattern here (async races, font/width estimation, missing CI
  hardware) — see
  [troubleshooting/03-e2e-ci-only-failures.md](../troubleshooting/03-e2e-ci-only-failures.md)
  for the causes and the rules to follow before adding new E2E assertions.

## Platform notes

- Desktop startup configures window roles, native title-bar behavior, backdrop,
  and multi-window services.
- Mobile startup configures system UI and permission-sensitive behavior.
- `CB_PIP_MODE=1` triggers the lightweight PiP process path.
- Windows MethodChannel contracts are indexed in
  [method-channels.yaml](../agent/native/method-channels.yaml).

_Last reviewed: 2026-09-13_
