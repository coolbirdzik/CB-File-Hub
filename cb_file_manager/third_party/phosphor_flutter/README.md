# phosphor_flutter (vendored, trimmed, patched)

Local replacement for `phosphor_flutter` 2.1.0, wired in through
`dependency_overrides` in `cb_file_manager/pubspec.yaml`.

## Why this exists

Flutter made `IconData` a **final class**, so it can no longer be extended:

```dart
// flutter/lib/src/widgets/icon_data.dart
@immutable
final class IconData { ... }
```

Upstream builds its whole API on subclassing it:

```dart
class PhosphorIconData extends IconData        // no longer legal
class PhosphorFlatIconData extends PhosphorIconData
```

which fails the build with:

```
error: The class 'IconData' can't be extended outside of its library
       because it's a final class.
```

There is no upgrade path. `2.1.0` is the newest release on pub.dev, and
upstream `main` still carries the identical broken declaration, so a `git:`
override buys nothing. Hence the local patch.

## What was changed

The generated constants construct `IconData` directly instead of going through
the subclass:

```dart
- static const acorn = PhosphorFlatIconData(0xeb9a, 'Light');
+ static const acorn = IconData(0xeb9a, fontFamily: 'PhosphorLight',
+     fontPackage: 'phosphor_flutter', matchTextDirection: true);
```

`fontFamily`, `fontPackage` and `matchTextDirection` are byte-for-byte what the
upstream constructor produced, and the package name is unchanged, so the bundled
fonts still resolve and **no call site or import in `lib/` needed editing**.

Dropped, because nothing in this app used them: `PhosphorIcon` (the app always
uses plain `Icon`), the `PhosphorIcons` union class, `PhosphorIconsStyle`, and
the Thin, Regular and Duotone styles.

Duotone is the one style that cannot be reproduced by this patch as-is: it
relied on the subclass to carry a second `IconData` for the underlying layer.
Restoring it means generating a `codePoint -> secondary` map and a replacement
`PhosphorIcon` that reads it.

## Regenerating

After bumping the pinned upstream version in `tool/regenerate.sh`:

```bash
bash third_party/phosphor_flutter/tool/regenerate.sh
```

Add a style by appending it to `STYLES` in that script.

## Licensing

Upstream is MIT; `LICENSE` is copied verbatim from the published package. The
icon fonts are MIT from the Phosphor Icons project.
