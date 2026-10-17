import 'package:flutter/material.dart';
import 'app_localizations.dart';
import 'chinese_localizations.dart';
import 'english_localizations.dart';
import 'turkish_localizations.dart';
import 'vietnamese_localizations.dart';

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['en', 'vi', 'tr', 'zh'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    // Return the appropriate localization implementation based on language code
    switch (locale.languageCode) {
      case 'en':
        return EnglishLocalizations();
      case 'tr':
        return TurkishLocalizations();
      case 'zh':
        return ChineseLocalizations();
      case 'vi':
      default:
        return VietnameseLocalizations();
    }
  }

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}
