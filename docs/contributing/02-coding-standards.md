# Coding Standards

- **Language & Style** Follow Effective Dart; embrace null safety; keep functions focused; name things clearly.
- **Structure** Mirror existing layouts: BLoCs in `lib/bloc/`, config in `lib/config/`, helpers in `lib/helpers/`, utils in `lib/utils/`, UI by feature under `lib/ui/`.
- **Logging** **NEVER use `print()` in production code.** Always use `AppLogger` from `lib/utils/app_logger.dart` with appropriate log levels (debug, info, warning, error, fatal).
- **Widgets** Keep widgets side-effect free, lift logic to blocs, extract reusable pieces into `ui/components/`, obey theme + spacing tokens.
- **Desktop pointer feedback** Selection/focus must paint on the first mouse-down frame even when a row supports double-click. Use the shared pointer-selection contract and timing tests in [the design-system guide](../ui-patterns/06-design-system.md#desktop-selection-and-double-click-timing); waiting for the double-tap timeout is a UI regression.
- **Errors** Throw specific exceptions, surface friendly messages, never swallow failures silently. Always log errors with `AppLogger.error()` including error object and stack trace.
- **Async** Prefer `async`/`await`, close streams/controllers, guard isolates.
- **Testing** Add unit/widget coverage for touched code paths; create goldens only for critical visuals.
- **Linting** Fix all `analysis_options.yaml` warnings before merging.
- **Commits** Use Conventional Commit prefixes.
- **Docs** Update public `///` docs and relevant files in `docs/` as features evolve.
