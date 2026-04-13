## Logging Framework

- **CRITICAL RULE** Never use `print()` statements in production code. Always use the logging framework.
- **Implementation** Import `utils/app_logger.dart` and use appropriate log levels:

  ```dart
  import 'package:cb_file_manager/utils/app_logger.dart';

  AppLogger.debug('Detailed debug info');
  AppLogger.info('General messages');
  AppLogger.warning('Warnings');
  AppLogger.error('Error message', error: e, stackTrace: st);
  AppLogger.fatal('Fatal errors');
  ```

- **Benefits** Structured logging with timestamps, colors, method traces, stack traces, and configurable log levels.
- **Configuration** Based on `logger` package; supports runtime log level adjustment via `AppLogger.setLevel(Level.info)`.

## Testing & Tooling

- **Test Harness** See `test/` and scripts documented in `docs/quality/01-testing-strategy.md`; infra includes `run_tests.dart`, `stable_tests.dart`, and CI-ready runners.
- **Desktop E2E** `integration_test/` on Windows (`--dart-define=CB_E2E=true`), Makefile `dev-test-e2e`, reporters, and CI — see `docs/quality/02-e2e-desktop-integration.md`.
- **Coverage Focus** Navigation flows and core widgets presently covered; expand for new galleries or services when modified.
- **Diagnostics** Use `AppLogger.debug()` for verbose logging during development; toggle log levels as needed.

## Platform Notes

- **Desktop** `window_manager` ensures minimum window size, hidden title bar, and maximized start on Windows.
- **Mobile** Startup configures full system UI overlays and leverages platform storage permissions via `PermissionStateService`.
- **PiP Mode** Environment variable `CB_PIP_MODE=1` triggers lightweight PiP-only window bootstrap.

_Last reviewed: 2025-10-25_
