import 'package:flutter/material.dart';
import 'languages/app_localizations.dart';
import 'languages/english_localizations.dart';

// Extension to make it easier to access translations
extension AppLocalizationsExtension on BuildContext {
  /// Falls back to English when the widget tree has no localizations delegate
  /// (isolated widgets, overlays hosted outside the app's `MaterialApp`).
  AppLocalizations get tr =>
      AppLocalizations.of(this) ?? EnglishLocalizations();
}
