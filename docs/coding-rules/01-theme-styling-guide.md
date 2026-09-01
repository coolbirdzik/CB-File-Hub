# Theme & Styling Guide

## Overview
CoolBird FM Flutter app follows strict theming rules to ensure consistent UI across the application. All UI components must use the theme system - **no hardcoded colors, sizes, or styles**.

## Core Principles

> **The design system supersedes parts of this guide.** See
> [`ui-patterns/06-design-system.md`](../ui-patterns/06-design-system.md).
> New code should use `context.cbColors` and the `Cb*` tokens/primitives.
> `theme.colorScheme.*` still works — it is now derived from the same tokens —
> so existing screens remain correct until they are migrated.

### 1. Use Theme Colors
**NEVER** hardcode colors. Prefer `context.cbColors.*` (semantic tokens);
`theme.colorScheme.*` is acceptable in un-migrated code.

### 2. Use Semantic Spacing
Use the `CbSpacing` / `CbRadii` / `CbSizes` scales, not arbitrary numbers.

### 3. Use Remix Icons
Prefer Remix Icons with `_line` suffix for consistency.

### 4. Follow the CoolBird design system
Build from `Cb*` primitives rather than Material widgets. Material 3 components
are still themed correctly, but they are the legacy path — see the design
system doc for what Material behaviour is deliberately switched off
(`surfaceTint`, ink ripple, `ColorScheme.fromSeed`).

### 5. Depth is a hairline border plus a shadow
Elevation comes from `CbElevation` shadows and 1px `c.stroke` borders, applied
through `CbSurface`'s levels — **not** from tinted surfaces. Keep surfaces
neutral; do not reintroduce `surfaceTint`. Flat (`CbSurfaceLevel.flat`) remains
the default for in-page content; reserve shadows for things that genuinely
float (menus, popovers, dialogs, toasts).

## Color System

### ❌ WRONG - Hardcoded Colors
```dart
// DON'T DO THIS
Container(
  color: Colors.blue,
  child: Text(
    'Hello',
    style: TextStyle(color: Colors.white),
  ),
)

Icon(PhosphorIconsRegular.x, color: Colors.red)
border: Border.all(color: Color(0xFF123456))
```

### ✅ CORRECT - Using Theme Colors
```dart
// DO THIS
final theme = Theme.of(context);

Container(
  color: theme.colorScheme.primary,
  child: Text(
    'Hello',
    style: TextStyle(color: theme.colorScheme.onPrimary),
  ),
)

Icon(PhosphorIconsRegular.x, color: theme.colorScheme.error)
border: Border.all(color: theme.dividerColor)
```

### Common Theme Colors

```dart
final theme = Theme.of(context);

// Primary colors
theme.colorScheme.primary          // Main brand color
theme.colorScheme.onPrimary        // Text on primary
theme.colorScheme.primaryContainer // Lighter primary variant
theme.colorScheme.onPrimaryContainer

// Surface colors
theme.colorScheme.surface          // Card/surface background
theme.colorScheme.onSurface        // Text on surface
theme.colorScheme.surfaceVariant   // Subtle surface variant
theme.colorScheme.onSurfaceVariant // Text on surface variant

// Background
theme.scaffoldBackgroundColor      // Screen background
theme.cardColor                    // Card background

// Semantic colors
theme.colorScheme.error            // Error/danger
theme.colorScheme.onError          // Text on error
theme.dividerColor                 // Dividers and borders
theme.shadowColor                  // Shadows

// Icon colors
theme.iconTheme.color              // Default icon color
```

### Opacity Usage
```dart
// Use standard opacity values
theme.colorScheme.onSurface.withOpacity(0.3)  // Very subtle
theme.colorScheme.onSurface.withOpacity(0.5)  // Subtle
theme.colorScheme.onSurface.withOpacity(0.7)  // Medium
```

## Spacing System

### Standard Spacing Values
Use these consistent spacing values:

```dart
// Spacing constants
const spacing4 = 4.0;
const spacing8 = 8.0;
const spacing12 = 12.0;
const spacing16 = 16.0;
const spacing20 = 20.0;
const spacing24 = 24.0;

// Usage
SizedBox(height: 16)
padding: EdgeInsets.all(16.0)
EdgeInsets.symmetric(horizontal: 16, vertical: 12)
```

### ❌ WRONG - Arbitrary Spacing
```dart
// DON'T DO THIS
SizedBox(height: 15)
padding: EdgeInsets.all(13.0)
margin: EdgeInsets.only(left: 7, top: 23)
```

### ✅ CORRECT - Semantic Spacing
```dart
// DO THIS
SizedBox(height: 16)
padding: EdgeInsets.all(16.0)
margin: EdgeInsets.only(left: 8, top: 24)

// For grids/lists
crossAxisSpacing: 16
mainAxisSpacing: 16
```

## Border Radius

### Standard Radius Values
```dart
// Border radius constants
const radius12 = 12.0;
const radius16 = 16.0;
const radius20 = 20.0;
const radius24 = 24.0;

// Usage
BorderRadius.circular(16)
borderRadius: BorderRadius.circular(12)
```

### ❌ WRONG
```dart
BorderRadius.circular(13)
BorderRadius.circular(27)
```

### ✅ CORRECT
```dart
BorderRadius.circular(12)
BorderRadius.circular(16)
BorderRadius.circular(20)
```

## Flat Design Philosophy

### No Drop Shadows
Avoid shadows across the app to keep the UI clean. Depth should come from color, spacing, and hierarchy — not elevation.

### ❌ WRONG - Excessive Borders
```dart
// DON'T DO THIS - Too many borders
Container(
  decoration: BoxDecoration(
    color: theme.cardColor,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      color: theme.dividerColor,
      width: 1.0,
    ),
  ),
  child: Container(
    decoration: BoxDecoration(
      color: theme.surfaceVariant,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: theme.dividerColor,
        width: 1.0,
      ),
    ),
  ),
)
```

### ✅ CORRECT - Flat Design with Backgrounds
```dart
// DO THIS - Clean, flat design
Container(
  decoration: BoxDecoration(
    color: theme.cardColor,
    borderRadius: BorderRadius.circular(16),
  ),
  child: Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          theme.colorScheme.surfaceVariant.withOpacity(0.3),
          theme.colorScheme.surfaceVariant.withOpacity(0.15),
        ],
      ),
      borderRadius: BorderRadius.circular(12),
    ),
  ),
)
```

### Visual Separation Techniques
Use these instead of borders and shadows:
1. **Background colors**: Different colors for grouping
2. **Gradients**: For visual interest and depth
3. **Spacing**: Adequate padding and margins
4. **Opacity**: Subtle background opacity differences
5. **Color contrast**: Use theme colors effectively

### Borders (Explicit Exceptions Only)
Borders can be used sparingly and only for:
1. **Input fields** — to indicate editable areas
2. **Focus states** — to show keyboard focus
3. **Dividers** — use `Divider` widget

Avoid borders on tiles/cards; use spacing, background tones, and radius.

## Component Rules

### File Grid (Folder/File list in grid mode)
- No shadows/elevation on tiles
- No borders — flat look by default
- Border radius: 8; clip thumbnail to radius
- Separation via grid spacing and subtle background tones when needed
- Selected state: background tint (primary 0.2 alpha) and check icon; no border
```dart
// Flat tile (no border/shadow)
ClipRRect(
  borderRadius: BorderRadius.circular(8),
  child: Stack(
    fit: StackFit.expand,
    children: [
      // thumbnail
      // selection overlay with tint
    ],
  ),
)
```

## Icon System

### Use Remix Icons with `_line` Suffix
```dart
import 'package:phosphor_flutter/phosphor_flutter.dart';

// ✅ CORRECT - Use _line icons
Icon(PhosphorIconsRegular.x)
Icon(PhosphorIconsRegular.plus)
Icon(PhosphorIconsRegular.folder)
Icon(PhosphorIconsRegular.files)

// ❌ WRONG - Don't use _fill unless specifically needed
Icon(PhosphorIconsFill.xCircle)
Icon(PhosphorIconsFill.folder)
```

### Icon Sizes
```dart
// Standard icon sizes
const iconSmall = 18.0;
const iconMedium = 22.0;
const iconLarge = 24.0;
const iconXLarge = 48.0;

// Usage
Icon(PhosphorIconsRegular.x, size: 20)
Icon(PhosphorIconsRegular.folder, size: 22)
Icon(PhosphorIconsRegular.files, size: 48)
```

## Typography

### Using Theme Text Styles
```dart
final theme = Theme.of(context);

// Headlines
Text(
  'Title',
  style: TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: theme.colorScheme.onSurface,
  ),
)

// Body text
Text(
  'Description',
  style: TextStyle(
    fontSize: 14,
    color: theme.colorScheme.onSurfaceVariant,
  ),
)

// Subtle text
Text(
  'Path',
  style: TextStyle(
    fontSize: 13,
    color: theme.colorScheme.onSurfaceVariant,
    height: 1.3,
  ),
)
```

### Font Weights
```dart
FontWeight.w400  // Regular (normal)
FontWeight.w500  // Medium
FontWeight.w600  // Semi-bold
FontWeight.w700  // Bold
```

## Common UI Patterns

### Card Design (Flat)
```dart
// Clean, flat card design
Container(
  decoration: BoxDecoration(
    color: theme.cardColor,
    borderRadius: BorderRadius.circular(16),
  ),
  padding: const EdgeInsets.all(16.0),
  child: // ... content
)
```

### Active/Selected State (Flat)
```dart
final isActive = true;

Container(
  decoration: BoxDecoration(
    gradient: isActive
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primaryContainer.withOpacity(0.4),
              theme.colorScheme.primaryContainer.withOpacity(0.2),
            ],
          )
        : null,
    color: isActive ? null : theme.cardColor,
    borderRadius: BorderRadius.circular(16),
  ),
)
```

### Button Styles

#### Icon Button
```dart
IconButton(
  icon: Icon(
    PhosphorIconsRegular.x,
    color: theme.colorScheme.onSurface,
  ),
  tooltip: localizations.close,
  onPressed: () {},
)
```

#### Text Button
```dart
TextButton.icon(
  icon: Icon(
    PhosphorIconsRegular.xCircle,
    color: theme.colorScheme.error,
    size: 20,
  ),
  label: Text(
    localizations.closeAllTabs,
    style: TextStyle(
      color: theme.colorScheme.error,
      fontWeight: FontWeight.w600,
    ),
  ),
  onPressed: () {},
)
```

#### Floating Action Button
```dart
FloatingActionButton.extended(
  onPressed: () {},
  icon: const Icon(PhosphorIconsRegular.plus),
  label: Text(localizations.addNewTab),
  backgroundColor: theme.colorScheme.primary,
)
```

### Touch Targets
Ensure buttons and interactive elements have adequate touch targets (minimum 48x48 dp):

```dart
// ✅ CORRECT - Larger touch target
Material(
  color: theme.colorScheme.error.withOpacity(0.1),
  borderRadius: BorderRadius.circular(20),
  child: InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: () {},
    child: Padding(
      padding: const EdgeInsets.all(8.0),  // Makes it easier to tap
      child: Icon(
        PhosphorIconsRegular.x,
        size: 20,
        color: theme.colorScheme.error,
      ),
    ),
  ),
)
```

## AppBar Styling

```dart
AppBar(
  elevation: 0,
  backgroundColor: theme.scaffoldBackgroundColor,
  leading: IconButton(
    icon: Icon(
      PhosphorIconsRegular.x,
      color: theme.colorScheme.onSurface,
    ),
    tooltip: localizations.close,
    onPressed: () {},
  ),
  title: Text(
    localizations.tabManager,
    style: TextStyle(
      color: theme.colorScheme.onSurface,
      fontSize: 20,
      fontWeight: FontWeight.w600,
    ),
  ),
)
```

## Grid Layouts

```dart
GridView.builder(
  padding: const EdgeInsets.all(16.0),
  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2,
    crossAxisSpacing: 16,
    mainAxisSpacing: 16,
    childAspectRatio: 0.85,
  ),
  itemBuilder: (context, index) {
    // ... item builder
  },
)
```

## Responsive Design

```dart
LayoutBuilder(
  builder: (context, constraints) {
    final width = constraints.maxWidth;
    int crossAxisCount = 2;
    if (width >= 600) crossAxisCount = 3;
    if (width >= 900) crossAxisCount = 4;

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        // ...
      ),
    );
  },
)
```

## Dark Mode Support

All theme colors automatically support dark mode:

```dart
// This works in both light and dark mode
Container(
  color: theme.scaffoldBackgroundColor,
  child: Text(
    'Hello',
    style: TextStyle(color: theme.colorScheme.onSurface),
  ),
)
```

## Testing Checklist

Before submitting code:

- [ ] No hardcoded colors (no `Colors.blue`, `Color(0xFF...)`)
- [ ] No arbitrary spacing values (use 4, 8, 12, 16, 20, 24)
- [ ] No arbitrary border radius (use 12, 16, 20, 24)
- [ ] Using Remix Icons with `_line` suffix
- [ ] All text uses theme colors
- [ ] Touch targets are at least 48x48 dp
- [ ] UI works in both light and dark mode
- [ ] Consistent spacing throughout

## Reference Examples

Good examples of theme usage:
- `lib/ui/tab_manager/mobile/mobile_tab_view.dart`
- `lib/ui/screens/gallery_hub/gallery_hub_screen.dart`
- `lib/ui/screens/video_hub/video_hub_screen.dart`

## Common Mistakes to Avoid

1. **Hardcoding colors**
   ```dart
   // ❌ WRONG
   color: Colors.blue

   // ✅ CORRECT
   color: theme.colorScheme.primary
   ```

2. **Inconsistent spacing**
   ```dart
   // ❌ WRONG
   padding: EdgeInsets.all(13.0)

   // ✅ CORRECT
   padding: EdgeInsets.all(16.0)
   ```

3. **Using fill icons**
   ```dart
   // ❌ WRONG
   Icon(PhosphorIconsFill.xCircle)

   // ✅ CORRECT
   Icon(PhosphorIconsRegular.x)
   ```

4. **Small touch targets**
   ```dart
   // ❌ WRONG
   IconButton(
     padding: EdgeInsets.zero,
     constraints: BoxConstraints(),
     icon: Icon(PhosphorIconsRegular.x, size: 12),
   )

   // ✅ CORRECT
   IconButton(
     icon: Icon(PhosphorIconsRegular.x, size: 20),
     padding: EdgeInsets.all(8.0),
   )
   ```

## Best Practices

1. **Always get theme at the start of build method**
   ```dart
   @override
   Widget build(BuildContext context) {
     final theme = Theme.of(context);
     // ... use theme throughout
   }
   ```

2. **Use semantic color names**
   - `primary` for main actions
   - `error` for destructive actions
   - `onSurface` for primary text
   - `onSurfaceVariant` for secondary text

3. **Maintain visual hierarchy**
   - Use font size and weight to establish hierarchy
   - Use opacity for less important elements
   - Use color to highlight important actions

4. **Be consistent**
   - Same spacing for similar elements
   - Same border radius for cards
   - Same icon sizes for similar contexts
