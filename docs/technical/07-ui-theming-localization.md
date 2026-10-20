## UI Standards & Theming

- **App Theme**: Uses `AppTheme`, `ThemeConfig`, and `ThemeFactory` in `cb_file_manager/lib/config/` to generate `ThemeData`.
- **Hybrid Design**: 
    - **Material 3**: Used as the base design language.
    - **Fluent UI**: `FluentThemeConfig` adapts Material tokens to Fluent UI for Windows-specific components, ensuring a native feel on desktop.
    - **Flat Philosophy**: Avoids borders and heavy elevations; prefers subtle shadows and opacity layers.
- **Mobile Galleries**: `ui/screens/media_gallery/` uses flat cards and reuses `MobileFileActionsController` for top action bars.
- **Desktop Preview Mode**: File browser supports `ViewMode.gridPreview` with a resizable right preview pane (video/image via existing viewers, PDF via `pdfx` `PdfView`).

## macOS Materials and Panel Motion

- `FluentChromeSurface` composites tint, blur and a subtle macOS edge in Flutter. Interactive surfaces never embed decorative `AppKitView` widgets: the engine's native platform-view containers have their own hit testing, independent of Flutter's `IgnorePointer` or a child NSView returning `nil`.
- Desktop appearance branches by OS: Windows retains Acrylic; macOS uses Glass. `ThemeProvider.desktopBackdropStrength` selects the correct preference. macOS seeds `desktop_glass_strength` from the legacy acrylic setting once, then persists it independently. Preview changes commit on slider release, including when the committed value equals the preview.
- `MacosGlassTheme` separates the 0–200% transparency and blur controls for both host themes, canvas, toolbar, drawer, panels and wallpaper. Transparency zero paints opaque surfaces. Content surfaces retain more tint than chrome, and every text-bearing surface increases its tint when necessary to protect primary/secondary text against black or white backdrops. The minimum contrast is 4.5:1, or the authored opaque contrast for intentionally muted palette tones. Blur alone cannot protect contrast against broad bright/dark areas.
- Glass blur persists independently as `desktop_glass_blur_strength` and updates Flutter chrome/wallpaper blur without changing transparency. Dynamic mode blends with the actual desktop/windows behind the app; wallpaper mode uses the selected image. AppKit owns the native blur kernel; no private blur-radius API is used.
- `WindowAcrylicService` configures a native `NSVisualEffectView` behind the Flutter content through the existing `cb_file_manager/macos_window` channel. The backdrop cannot receive mouse events. Wallpaper mode removes it and keeps the user-selected image.
- `FluentSurfaceTokens` shares title-row, traffic-light and sidebar geometry. macOS uses a 60-point title row, wider rounded tabs and an inset sidebar with compact navigation rows and neutral selection. Windows retains its existing geometry and selection rail.
- `CbPanelReveal` owns retained opening/closing transitions for the AI sidebar and Status Center. Closing immediately disables input and focus, then releases the child after the exit finishes. Reopening reverses the transition. Reduced motion skips the animation; high contrast uses opaque chrome without blur.
- Native material changes require a rebuilt macOS app. Widget tests cover input, absence of decorative platform views, theme changes, panel lifecycle and interrupted/reduced motion. They do not establish native mouse routing or appearance in the running macOS app.

## macOS Sidebar Favorites

- The existing pinned section becomes Favorites on macOS. Foundation resolves Applications, Desktop, Documents, Downloads, the user's home, Pictures, Music and Movies through `getSidebarUserFolders`; only existing directories are offered. Other platforms retain manual pins.
- `SidebarPinsRepository` seeds these paths once, merging existing pins without duplicates. The paths and `macos_sidebar_defaults_v1` marker commit in one SQLite transaction, shared with manual pin mutations. The JSON path-list format remains compatible with context menus, other windows and backups. An unavailable folder is never deleted merely by validating the list.
- The first seed opens Favorites for existing accounts; later collapse state and removals persist. Both sidebar renderers use `SidebarPinnedEntry` for localized labels and folder-specific icons, and keep navigation on the existing tab path flow.

## Localization (Mandatory)

- **Rule**: All user-facing strings must go through i18n keys.
- **Implementation**: Import `cb_file_manager/lib/config/languages/app_localizations.dart` or call `context.tr.keyName`.
- **Adding Keys**: Update `app_localizations.dart`, `english_localizations.dart`, and `vietnamese_localizations.dart` in tandem.
- **Reference**: `docs/coding-rules/02-i18n-internationalization-guide.md` documents the workflow.

_Last reviewed: 2026-03-07_
