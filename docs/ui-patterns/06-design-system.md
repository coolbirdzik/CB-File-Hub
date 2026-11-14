# CoolBird Design System

**Purpose**: Give the app one visual language of its own, replacing Material Design's defaults with tokens and primitives we control.

## Overview

The design system lives in `cb_file_manager/lib/design_system/`. It has two layers:

- **Tokens** — the raw decisions (colour, spacing, radius, type, motion, elevation).
- **Primitives** — the widgets that consume them (`CbButton`, `CbSurface`, `CbTextField`, `CbDialog`).

Everything is reachable through one import:

```dart
import 'package:cb_file_manager/design_system/cb_design_system.dart';
```

### Why not just theme Material?

That was the previous approach and it plateaued. Three Material behaviours survive any amount of `ThemeData` tweaking and are what make an app *read* as Material:

| Material behaviour | What the design system does |
| --- | --- |
| `ColorScheme.fromSeed` runs a tonal-palette algorithm over your seed — it rotates hue, clamps chroma, and picks contrast targets | `CbThemeBuilder._colorScheme` assembles the scheme field by field from tokens; the accent reaches the UI unmodified |
| `surfaceTint` tints surfaces with the primary colour as they rise, so cards drift blue | `surfaceTint` is transparent everywhere; depth is a shadow plus a hairline border |
| The ink ripple animates out from a touch point on every tap | `NoSplash` + hover/press colour states, the pointer-driven convention |

## Tokens

Colour is the only family that varies by theme, so it is the only one requiring a `BuildContext`:

```dart
final c = context.cbColors;          // CbColorTokens
final tokens = context.cb;           // CbTokens (colours + shadows + brightness)

Container(
  padding: const EdgeInsets.all(CbSpacing.md),   // 12 — compile-time constant
  decoration: BoxDecoration(
    color: c.surfaceRaised,
    borderRadius: CbRadii.mdAll,                 // 8
    border: Border.all(color: c.stroke),
    boxShadow: tokens.shadowLevel1,
  ),
  child: Text('Documents', style: CbTypography.body.copyWith(color: c.textPrimary)),
)
```

### Scales at a glance

| Family | File | Values |
| --- | --- | --- |
| Spacing | `tokens/cb_geometry_tokens.dart` | `xxs` 2 · `xs` 4 · `sm` 8 · `md` 12 · `lg` 16 · `xl` 24 · `xxl` 32 · `xxxl` 48 |
| Radius | same | `xs` 4 · `sm` 6 · `md` 8 · `lg` 12 · `xl` 16 · `button` 8 · `full` |
| Control height | same | `controlXs` 24 · `controlSm` 28 · `controlMd` 32 · `controlLg` 40 |
| Type | `tokens/cb_type_tokens.dart` | Inter 400/500/600; `body` is **13/18** — the app's default UI size |
| Motion | `tokens/cb_motion_tokens.dart` | `instant` 80ms · `fast` 140ms · `normal` 220ms · `slow` 320ms |
| Elevation | `tokens/cb_elevation_tokens.dart` | `level0`–`level4`, two-part shadows |

The radius and spacing scales top out much lower than Material's. M3's 20px pill on every button and card is the single most recognisable tell of a Material app; 6–8px is the working range for rows, inputs, cards and buttons, 12px for menus and popovers, 16px for dialogs and the command palette, and `full` is reserved for genuinely pill-shaped things (chips, avatars, progress tracks).

### The look: Raycast-style

| Rule | Where it lives |
| --- | --- |
| **Neutral greys.** `CbNeutral` carries only a trace of blue, so panels never read as "themed". | `tokens/cb_color_tokens.dart` |
| **Resting chrome is borderless.** Cards, buttons and chips separate from the page by a step on the translucent fill ramp. | `CbThemeBuilder`, `CbSurface` |
| **Floating layers get a hairline.** Menus, popovers, dialogs, tooltips, snackbars and the palette draw a 1px `c.stroke` edge (`CbDecorations.floatingEdge`) plus a soft, wide shadow, so they read on the acrylic backdrop. | `CbDecorations.floating`, `floatingShape` |
| **Selection is neutral.** Selected rows, tabs, chips, segments and sidebar items use a grey wash and primary text. `selectionFill` stays at least twice as far off the canvas as hover. Media tiles add a 2px primary-text ring (`selectedOverlay`). | `CbDecorations.selectionFill`, `ItemInteractionStyle` |
| **The accent is rare.** One primary action per screen, plus state: focus ring, switches, checkboxes, progress, drop targets. | — |
| **Fields are hairline boxes** that brighten on hover and focus (`c.textTertiary`) and turn danger on error — no Windows-style bottom indicator. | `CbDecorations.field`, `inputBorder` |
| **Rows inside menus are inset and rounded**, 32px tall, with icons one step quieter than labels. | `shared_file_context_menu.dart` |

`test/design_system/cb_design_system_test.dart` asserts the borderless/hairline split and neutral selection.

### Colour

`CbColorTokens` is the semantic layer and the only one widgets should touch — `surface`, `textSecondary`, `stroke`, `accent.base`. Underneath it, `CbNeutral` is a cool-tinted grey ramp (hue ≈ 220, so greys stay coherent with the accents), and `CbAccentRamp` generates tints and shades around whichever of the nine accents the user picked.

Two ramp values are derived by *measuring* WCAG contrast rather than by a lightness rule:

- `accent.text` — the accent as text on a neutral surface, darkened (or lightened, in dark mode) in 0.02 steps until it clears 4.5:1.
- `accent.onBase` — near-white or near-black, whichever contrasts better with the fill.

This matters because contrast does not track lightness evenly across hues: teal `#00B294` and a blue of the same HSL lightness land on opposite sides of the threshold. `test/design_system/cb_design_system_test.dart` asserts all nine accents pass in both themes.

Status colours (`c.status.danger`, `.success`, …) are independent of the accent — a destructive action must read as destructive even when the user's accent is green.

## Primitives

| Widget | Replaces | Notes |
| --- | --- | --- |
| `CbPressable` | `InkWell` | Hover/press colour instead of ripple; Space/Enter activation; 2px focus ring |
| `CbButton` | `ElevatedButton`, `OutlinedButton`, `TextButton`, `IconButton` | 6 variants × 4 sizes; `CbButton.icon` for icon-only (tooltip required) |
| `CbSurface` | `Card`, `Material`, ad-hoc `Container(decoration:)` | 5 depth levels; neutral at every level |
| `CbTextField` | `TextField` + `InputDecoration` | 32px tall, static label above the field, no floating label |
| `CbDialog` | `AlertDialog` | Built on `CbSurface`; `showCbConfirmDialog` covers the common case |
| `CbKbd` | hand-drawn shortcut labels | Key caps (`Ctrl` `K`, `↵`, `Esc`) for menus and the command palette |

## Library toolbar actions

Image Gallery, Albums and album contents keep their create/add action on the
top toolbar, immediately before the more menu. Video Gallery puts **Create
video library** beside refresh on the same bar. Media screens do not duplicate
these commands as floating buttons. Video-library file selection is available
through the existing more menu instead of a second floating selection button.

`SharedActionBar.buildCommonActions` accepts a `primaryAction` and an opt-in
`compact` layout. Gallery/album callers enable it below 640 px: create/add stays
visible, and search, sort, view, grid-size and refresh commands move into the
more menu. Closing an active search stays on the bar. The compact menu reuses
the full toolbar's allowed sort/view entries and callbacks; album shuffle,
edit and smart-rule commands remain available there too. Other callers retain
their existing layout unless they opt in.
Image/video source dialogs also wrap their source heading and add-directory
button onto separate lines when the available width is small.

`LibraryHubScaffold` hosts toolbar actions only; it has no floating-action API.
Widget coverage for compact callbacks lives in
`test/ui/components/common/shared_action_bar_compact_test.dart`; album and video
screen tests cover creation, navigation, selection, search and view preferences.

## Desktop selection and double-click timing

Selection, focus and pressed feedback must appear on the first pointer frame.
Do not put desktop selection only in `GestureDetector.onTap` when the same
control has `onDoubleTap`: the first tap waits for the double-tap timeout.
`onTapDown` alone is also insufficient inside a scrollable, where gesture
arbitration can wait for Flutter's press timeout. This can make a cheap state
update look like slow rendering.

For selectable desktop rows/cards, use the shared primitives:

```dart
CbSurface(
  selected: isSelected,
  pressOnPointerDown: isDesktop,
  onPressed: selectAndFocus, // Primary mouse down; called once per press.
  onDoubleTap: open,
  onActivate: open,         // Keyboard Space/Enter.
  child: content,
)
```

`CbPressable` handles immediate primary-mouse selection with a raw `Listener`,
suppresses the later `onTap` callback, and clears pressed feedback on pointer
up/cancel. A delayed gesture callback must not make the released row look
pressed again. `CbSurface` paints selection/focus/press without an additional
transition delay in this mode. Touch keeps normal tap/scroll arbitration.

Enable `pressOnPointerDown` only for reversible selection/focus. Keep opening,
navigation and destructive actions on committed gestures. Preserve double-click,
dragging, context menus, child buttons and keyboard activation; do not work around
the delay by removing double-click or shortening global gesture timeouts.

Regression tests must use a mouse pointer down followed by `pump()` with no
elapsed duration, assert selection/pressed feedback, then release and assert
feedback clears immediately. Check exactly one selection per press, one open per
double-click, cancellation, secondary buttons, child actions, touch scrolling and
keyboard activation. A test that waits 300–400 ms before asserting selection
cannot detect this regression.

Coverage: `test/design_system/primitives/cb_pressable_pointer_test.dart` and
`test/ui/screens/home/drive_browser_content_test.dart`.

## Command palette (Ctrl/⌘+K)

`ui/components/command_palette/` is the Raycast-style launcher: a frosted, hairline-edged window with a borderless search row, grouped results and a footer of key hints. `showCommandPalette` takes items that are ready now, a `deferredItems` future merged in when it resolves (so the palette opens instantly), and `itemsForQuery` for query-dependent rows. `rankCommandPaletteItems` keeps section order and ranks titles by prefix, word start, then substring, using `TextUtils.searchKey`, so matching is accent-insensitive.

The tab shell wires it in `ui/tab_manager/core/tab_command_palette.dart`: open tabs, the entries of the active tab's folder (only once the user types; capped per section), places (Home, Drives, Gallery, …, Settings), pinned and recent folders, tab commands (new tab/window, close tab, split view, theme, keyboard shortcuts) and a "go to" row whenever the query looks like a path. Nothing on the per-keystroke path touches the disk; the path is resolved when the row runs. Files open the way a double-click does (images in the app viewer, videos in the app player). The shortcut is `OpenCommandPaletteIntent` in `tab_keyboard_shortcuts.dart`; Ctrl+K again, or Esc, closes it. Tests: `test/ui/components/command_palette_test.dart`.

## Keyboard shortcuts reference

`ui/components/keyboard_shortcuts/` holds the shortcut reference shown in **Settings → Keyboard shortcuts**, from the palette ("Keyboard shortcuts") and from the Home keyboard tip.

- `KeyCaps` renders every combo — palette rows, the Home tip, the reference — so they look the same everywhere: ⌘ ⌥ ⇧ ⌃ on macOS, Ctrl/Alt/Shift elsewhere.
- `keyboard_shortcut_catalog.dart`: the **tabs & windows** group is generated from `tabKeyboardShortcuts()`, the map the shell installs, and `tabShortcutLabel` must name every intent in it (`test/ui/components/keyboard_shortcuts_test.dart` fails otherwise). The file list, image viewer, video player and editor groups are hand-listed from their handlers — update them when a handler changes.
- `KeyboardShortcutsView` is one view with two hosts: `KeyboardShortcutsScreen` (Settings page) and `showKeyboardShortcutsDialog` (floating window).

The Home tip (`ui/screens/home/home_keyboard_tip.dart`, desktop only) teaches Ctrl+K, Ctrl+T and type-to-find. Its button opens the palette through `Actions.maybeInvoke(OpenCommandPaletteIntent)`, so it uses the shell's own action. Dismissing it clears `UserPreferences.showHomeKeyboardTip`; the switch at the top of the shortcuts reference turns it back on.

```dart
CbButton(
  label: 'Delete permanently',
  icon: PhosphorIcons.trash(),
  variant: CbButtonVariant.danger,
  onPressed: _delete,
)

final confirmed = await showCbConfirmDialog(
  context: context,
  title: 'Delete 12 items?',
  message: 'This cannot be undone.',
  destructive: true,
);
```

Button variants are hierarchical, not decorative: at most one `primary` per screen, a few `secondary`, any number of `subtle`/`ghost`. Material's five overlapping button types invite inconsistency because the difference between them carries no meaning.

## Migration

`CbThemeBuilder` is the bridge. `ThemeConfig.getLightTheme()` / `getDarkTheme()` now delegate to it, so **every screen already picks up the new colours, radii and type** — including the ~150 files still built from Material widgets. Each component theme (`cardTheme`, `inputDecorationTheme`, `elevatedButtonTheme`, …) is derived from the same tokens the primitives use, so an un-migrated `ElevatedButton` and a `CbButton` look the same.

That makes migration incremental rather than a flag day:

1. New UI is built from primitives and tokens. No new hard-coded colours, paddings or radii.
2. Existing screens move over when they are being touched anyway. Swapping `ElevatedButton` → `CbButton` should be visually near-neutral; if it is not, the theme bridge has a gap worth fixing.
3. Replace magic numbers with token references as you go — that is what stops the two systems drifting apart.

### Things to know

- **Acrylic.** `AppThemeResolver.createAcrylicBridgeTheme` bridges both the `ColorScheme` *and* the `CbTokens` surfaces, so `CbSurface` goes translucent over a Windows acrylic backdrop. Overlay surfaces (menus, popovers) stay solid deliberately — stacking two blurs stops being readable.
- **Extensions.** `CbThemeBuilder` owns the theme's extension list. Anything else that needs to ride along (e.g. `AppToastTheme`) must be passed as `extraExtensions`, not bolted on with `copyWith(extensions: …)` — that would drop `CbTokens`.
- **Fonts are bundled, not borrowed.** **Inter** (UI) and **JetBrains Mono** (paths, hashes, byte counts) live in `assets/fonts/`, declared in `pubspec.yaml`. Only the three weights the scale uses are shipped — 400/500/600 — plus mono regular, about 1.5 MB total. A system-font stack would render as Segoe UI on Windows, SF on macOS and Roboto on Android, so the app would never look like one product; bundling is what makes the type an identity.
  - Both are **SIL Open Font License 1.1**: free for commercial use and redistributable inside the app. The OFL requires the licence to travel with the font, so `registerCbFontLicenses()` (called from `runCbFileApp()`) puts both texts in Flutter's standard licence page.
  - Both cover the full Vietnamese range including the đồng sign (₫, U+20AB) — verified against the fonts' `cmap` before bundling. `uiFallback` / `monoFallback` remain for glyphs neither family has (CJK, emoji).
