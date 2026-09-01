# Execution Flow

## Initialization order

- `lib/main.dart` parses window roles and E2E flags, initializes Flutter and
  platform bindings, and configures desktop or mobile behavior.
- Desktop window setup, rendering caches, MediaKit, and streaming are prepared
  before the main application is mounted where the active window role requires
  them.
- `setupServiceLocator()` registers long-lived services. Preferences and
  language initialize before data-backed UI is mounted.
- SQLite, network credentials, and tag services initialize before thumbnail and
  album services.
- Secondary windows can defer selected expensive initializers until after their
  first frame. PiP mode takes a lightweight root path.

## Service bootstrapping

- `lib/core/service_locator.dart` is the registration source of truth.
- Registration and initialization are separate: lazy singletons do not become
  ready merely because `setupServiceLocator()` completed.
- `lib/main.dart` remains the authoritative call sequence for startup wiring.

## Platform branches

- Desktop paths configure `window_manager`, native window utilities, backdrop,
  and multi-window roles.
- Mobile paths configure system UI overlays and permission-sensitive behavior.
- `CB_PIP_MODE=1` selects the PiP-only application path.

## Root UI and navigation

- `CBFileApp` chooses Fluent or Material roots through design-system flags and
  mounts `TabMainScreen` as the normal home.
- Navigation is primarily tab and system-path based. See
  [Navigation & State Management](03-navigation-state.md).
- For complete flow diagrams, see
  [Agent Graph — Core Execution Flows](../agent/flows/core-flows.md).

_Last reviewed: 2026-08-08_
