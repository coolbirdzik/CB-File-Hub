## UI Standards & Theming

- **App Theme**: Uses `AppTheme`, `ThemeConfig`, and `ThemeFactory` in `cb_file_manager/lib/config/` to generate `ThemeData`.
- **Hybrid Design**: 
    - **Material 3**: Used as the base design language.
    - **Fluent UI**: `FluentThemeConfig` adapts Material tokens to Fluent UI for Windows-specific components, ensuring a native feel on desktop.
    - **Flat Philosophy**: Avoids borders and heavy elevations; prefers subtle shadows and opacity layers.
- **Mobile Galleries**: `ui/screens/media_gallery/` uses flat cards and reuses `MobileFileActionsController` for top action bars.
- **Desktop Preview Mode**: File browser supports `ViewMode.gridPreview` with a resizable right preview pane (video/image via existing viewers, PDF via `pdfx` `PdfView`).

## Localization (Mandatory)

- **Rule**: All user-facing strings must go through i18n keys.
- **Implementation**: Import `cb_file_manager/lib/config/languages/app_localizations.dart` or call `context.tr.keyName`.
- **Adding Keys**: Update `app_localizations.dart`, `english_localizations.dart`, and `vietnamese_localizations.dart` in tandem.
- **Reference**: `docs/coding-rules/i18n-internationalization-guide.md` documents the workflow.

_Last reviewed: 2026-03-07_
