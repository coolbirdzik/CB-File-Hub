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
    borderRadius: CbRadii.mdAll,                 // 7
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
| Radius | same | `xs` 3 · `sm` 5 · `md` 7 · `lg` 10 · `xl` 14 · `full` |
| Control height | same | `controlXs` 24 · `controlSm` 28 · `controlMd` 32 · `controlLg` 40 |
| Type | `tokens/cb_type_tokens.dart` | Inter 400/500/600; `body` is **13/18** — the app's default UI size |
| Motion | `tokens/cb_motion_tokens.dart` | `instant` 80ms · `fast` 140ms · `normal` 220ms · `slow` 320ms |
| Elevation | `tokens/cb_elevation_tokens.dart` | `level0`–`level4`, two-part shadows |

The radius and spacing scales top out much lower than Material's. M3's 20px pill on every button and card is the single most recognisable tell of a Material app; 5–7px is the working range here, and `full` is reserved for genuinely pill-shaped things (chips, avatars, progress tracks).

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
