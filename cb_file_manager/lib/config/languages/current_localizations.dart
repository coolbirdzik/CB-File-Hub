import '../language_controller.dart';
import 'app_localizations.dart';
import 'chinese_localizations.dart';
import 'english_localizations.dart';
import 'turkish_localizations.dart';
import 'vietnamese_localizations.dart';

/// Strings for the language the app is currently using.
///
/// For code that has no `BuildContext` to look localizations up with (BLoCs,
/// services). Widgets should keep using `context.tr`.
AppLocalizations get currentL10n =>
    switch (LanguageController().currentLocale.languageCode) {
      'vi' => VietnameseLocalizations(),
      'tr' => TurkishLocalizations(),
      'zh' => ChineseLocalizations(),
      _ => EnglishLocalizations(),
    };
