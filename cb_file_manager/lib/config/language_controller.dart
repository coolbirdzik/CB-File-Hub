import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageController {
  // Singleton instance
  static final LanguageController _instance = LanguageController._internal();
  factory LanguageController() => _instance;
  LanguageController._internal();

  // Available languages
  static const String vietnamese = 'vi';
  static const String english = 'en';

  // Default language
  static const String defaultLanguage = vietnamese;

  // Controller for language changes
  final _languageController =
      ValueNotifier<Locale>(const Locale(defaultLanguage));
  ValueNotifier<Locale> get languageNotifier => _languageController;

  // Key for storing language preference
  static const String _languageKey = 'selected_language';

  // Get current language
  Locale get currentLocale => _languageController.value;

  // Initialize language from saved preferences
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLanguage = prefs.getString(_languageKey) ?? defaultLanguage;
    _languageController.value = Locale(savedLanguage);
  }

  // Change language
  Future<void> changeLanguage(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, languageCode);
    _languageController.value = Locale(languageCode);
  }

  // Get language name for display
  String getLanguageName(String languageCode) {
    switch (languageCode) {
      case vietnamese:
        return 'Tiếng Việt';
      case english:
        return 'English';
      default:
        return 'Unknown';
    }
  }

  // Get all supported languages
  List<String> get supportedLanguages => [vietnamese, english];
}
