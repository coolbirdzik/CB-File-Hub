# Testing Strategy

- **Goal** Fast feedback with enough coverage to block regressions.
- **Layers** Cover edge cases in unit/widget/service tests; retain desktop E2E for actual app wiring, decoding, native drag/drop, IPC and accessibility.
- **Desktop E2E** `just e2e-desktop` builds/launches the shared Windows entrypoint once; `just e2e-desktop-failed` only retries failed suites. See [commands, fixtures and reports](02-e2e-desktop-integration.md).
- **Focus Areas** Services/blocs, helper parsing, navigation + gallery/file flows.
- **Tooling** Use the existing `flutter_test`/`integration_test` stack and injected fakes. Do not add another framework to compensate for waits or repeated builds.
- **Fixtures** Keep unit/widget dependencies controlled. Service/native tests use temporary real DB/files or loopback servers; never user data or public network timing.
- **CI** Format, analyze and all unit/widget tests precede affected Windows E2E. Main/release require the full desktop gate; source-matched trusted passes can be reused.
- **Coverage** Use uncovered behavior to guide regression tests. A percentage alone does not prove a user flow, and there is no claim here that a numeric coverage gate is enforced.
- **Structure** Mirror `lib/` under `test/`, name files `<target>_test.dart`.
- **Non-Functional** Track performance on heavy lists/streams and verify retry/backoff logic.
- **Assertions** A missing dialog/action must fail, not skip the interaction. Wait for observable results with deadlines; verify file bytes, state changes and error UI. Missing terminal events, skipped-only suites and empty filters cannot count as passes.
- **Reports** Treat skip/fail/incomplete as distinct. Use JSON event timestamps, attach screenshots by exact test identity and replace stale Allure result files.
- **Measurements** [Windows test-harness benchmark](04-test-performance.md) records scope, raw timings and limitations.
