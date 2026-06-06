# Tab Inactive Management

**Purpose**: Automatically release RAM from idle tabs by tracking per-tab activity and suspending caches after a configurable inactivity threshold.

## How it works

Each tab has one of three lifecycle states:

| State | Meaning |
|-------|---------|
| `focused` | Currently visible and active |
| `backgroundActive` | Open but not focused; background work runs at lower priority |
| `inactive` | Idle longer than the threshold; caches released, reload required on refocus |

A periodic timer (every 1 minute) evaluates all background tabs. If a tab's last interaction exceeds the threshold (default 60 minutes), it transitions to `inactive`.

## State transitions

```
focused ──── loses focus ────► backgroundActive
   ▲                                │
   │                                │ idle > threshold
   │                                ▼
   └──── user refocuses ◄──── inactive
           (needsReload)
```

When an inactive tab is refocused:
1. It promotes back to `focused`.
2. A `needsReload` flag is set and consumed once.
3. The tab's folder contents are fully reloaded from disk/network.

## What gets released on inactive

`TabCacheReleaseHelper.releaseForTab()` runs when a tab transitions to inactive:

- Directory listing cache for the tab's path
- Photo thumbnail memory cache entries
- Pending video thumbnail work
- Folder thumbnail work
- Network/SMB thumbnail queues for the tab's prefix
- Suspends `ThumbnailLoader` for the tab (via `ThumbnailLoaderSuspendRegistry`)
- Trims the global Flutter image cache if it exceeds 96 MiB

## User controls

- **Threshold setting**: `Settings → Performance → Tab inactive threshold`. Set to 0 to disable auto-suspend entirely.
- **Always-active pin**: Right-click a tab → "Keep active". Pinned tabs are never auto-suspended and show a pin icon.
- **Manual suspend**: Right-click a tab → "Suspend tab". Immediately transitions a background tab to inactive.

## UI indicators

- **Moon icon** (`TabInactiveIndicator`): shown on inactive tabs. Disappears on refocus.
- **Pin icon** (`TabAlwaysActiveIndicator`): shown on always-active pinned tabs.

## Key files

| File | Purpose |
|------|---------|
| `lib/services/tab_activity/tab_activity_manager.dart` | Core manager: state machine, periodic evaluation, listeners |
| `lib/services/tab_activity/tab_cache_release_helper.dart` | Cache release logic on inactive transition |
| `lib/ui/tab_manager/components/tab_inactive_indicator.dart` | Moon icon widget |
| `lib/ui/tab_manager/components/tab_always_active_indicator.dart` | Pin icon widget |
| `lib/helpers/core/user_preferences.dart` | `tab_inactive_threshold_minutes` preference |
| `lib/core/service_locator.dart` | Singleton registration |

## Configuration

The threshold is stored in `SharedPreferences` under key `tab_inactive_threshold_minutes`:

- Default: `60` (minutes)
- `0` disables auto-suspend entirely (all tabs stay active)
- Changing the threshold at runtime affects the next evaluation cycle immediately

## Testing

Unit tests cover all state transitions, edge cases, and the suspend registry:

- `test/10_tab_activity_manager_test.dart` — 21 tests for focus/background/inactive transitions, pinning, manual suspend, threshold changes
- `test/13_thumbnail_loader_suspend_registry_test.dart` — 6 tests for path-prefix suspend/resume logic
