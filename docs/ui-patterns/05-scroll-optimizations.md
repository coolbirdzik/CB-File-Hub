# Scroll Optimizations

**Purpose**: Keep the UI smooth during fast scrolling and provide Ctrl+scroll zoom for grid density control.

## Scroll Velocity Tracking

### Problem

Generating thumbnails (video frames, image resizes, folder covers) is expensive. When a user scrolls quickly through hundreds of items, triggering thumbnail work for every visible item causes frame drops and wasted computation (items scroll out of view before the thumbnail completes).

### Solution

A global `ScrollVelocityNotifier` singleton tracks scroll velocity using an exponential moving average. When velocity exceeds 800 px/s, a `isScrollingFast` flag goes true. Thumbnail loaders check this flag and defer expensive work until scrolling settles.

### Architecture

```
ScrollVelocityListener (widget)
    ↓ feeds ScrollNotification deltas
ScrollVelocityNotifier (global singleton)
    ↓ exposes ValueNotifier<bool> isFastScrolling
ScrollVelocityAware (mixin)
    ↓ reactive isScrollingFast getter
ThumbnailLoader / LazyVideoThumbnail
    → skip/defer generation when isScrollingFast == true
```

### Usage

Wrap any scrollable view with `ScrollVelocityListener`:

```dart
ScrollVelocityListener(
  child: ListView.builder(...),
)
```

In thumbnail widgets, use the `ScrollVelocityAware` mixin:

```dart
class _MyThumbnailState extends State<MyThumbnail>
    with ScrollVelocityAware {
  @override
  Widget build(BuildContext context) {
    if (isScrollingFast) return placeholder;
    return actualThumbnail;
  }
}
```

### Thresholds

| Parameter | Value | Notes |
|-----------|-------|-------|
| Fast-scroll threshold | 800 px/s | EMA-smoothed; avoids flickering |
| Settle delay | ~150 ms | After velocity drops, brief debounce before resuming work |

### Key files

| File | Purpose |
|------|---------|
| `lib/ui/utils/scroll_velocity_notifier.dart` | Global notifier, listener widget, mixin |
| `lib/ui/widgets/thumbnail_loader.dart` | Defers thumbnail loading during fast scroll |
| `lib/ui/widgets/lazy_video_thumbnail.dart` | Pauses video thumbnail on fast scroll |
| `lib/ui/widgets/file_list_view_builder.dart` | Wraps file list/grid with ScrollVelocityListener |

---

## Ctrl+Scroll Zoom (View Scale)

### What it does

Ctrl+scroll (Cmd+scroll on macOS) adjusts the view density:
- **Scroll up** (with Ctrl held) → bigger items / fewer columns (zoom in)
- **Scroll down** (with Ctrl held) → smaller items / more columns (zoom out)

On pages that support multiple view modes, the zoom extends beyond grid columns into a full **view-mode spectrum**: scrolling past the densest grid transitions into list view, then details, then columns, then tree (densest).

### Architecture

```
CtrlScrollZoom (widget)
    ↓ intercepts PointerScrollEvent when Ctrl/Meta held
    ↓ emits +1 or -1 delta
FileViewShell (composite wrapper)
    ↓ routes delta to either:
    │   onGridZoomDelta (legacy: grid only)
    │   onViewScaleDelta (unified: all modes)
    ↓
ViewModeSpectrum.step() (pure function)
    → returns ViewSpectrumResult(mode, gridZoomLevel)
```

### View Mode Spectrum

The spectrum orders all view modes from densest to most spacious:

```
tree → columns → details → list → grid(maxZoom) → ... → grid(minZoom)
(densest)                                                (most spacious)
```

Each `delta = +1` moves one stop toward spacious; `delta = -1` moves toward dense. Grid mode has multiple stops (one per zoom level). Non-grid modes are single stops.

Pages declare which modes they support:
- File browser: `{tree, columns, details, list}` + grid
- Tag manager: `{tree, list}` + grid
- Network browser: `{tree, details, list}` + grid

### Grid zoom level

The zoom level is the number of columns at a 960 px reference width:
- `minGridZoomLevel` (2) = biggest items, fewest columns
- `maxGridZoomLevel` (dynamic, viewport-dependent) = smallest items, most columns

The actual column count adapts to the real viewport width using `GridZoomConstraints`.

### Key files

| File | Purpose |
|------|---------|
| `lib/ui/widgets/ctrl_scroll_zoom.dart` | Canonical Ctrl+scroll → ±1 delta widget |
| `lib/ui/components/common/file_view_shell.dart` | Composite wrapper: zoom + shortcuts + mouse nav |
| `lib/ui/utils/view_mode_spectrum.dart` | Pure spectrum stepping logic |
| `lib/ui/utils/grid_zoom_constraints.dart` | Viewport-aware column count calculations |
| `lib/helpers/core/user_preferences.dart` | Persists `grid_zoom_level` per context |

### Implementation checklist for new pages

1. Wrap the scrollable content in `CtrlScrollZoom` (or use `FileViewShell` which includes it).
2. Route the `onDelta` callback to `ViewModeSpectrum.step()` with the page's supported modes.
3. Apply the returned `ViewSpectrumResult.mode` and `.gridZoomLevel`.
4. Persist the zoom level via `UserPreferences` so it survives restarts.
5. Clamp `gridZoomLevel` against `GridZoomConstraints.maxGridSizeForContext()` on every build (viewport may have resized).
