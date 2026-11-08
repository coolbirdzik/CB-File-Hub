import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/language_controller.dart';
import 'subtitle_languages.dart';
import 'subtitle_srt.dart';

export 'subtitle_languages.dart';
export 'subtitle_srt.dart' show SubtitleFileMode;

/// Shared by Settings and every desktop player, including a separate video window.
class SubtitlePreferences extends ChangeNotifier {
  static SubtitlePreferences? _shared;
  static SubtitlePreferences shared(SharedPreferences prefs) {
    if (_shared == null || !identical(_shared!.prefs, prefs)) {
      _shared?.dispose();
      _shared = SubtitlePreferences(prefs);
    }
    return _shared!;
  }

  final SharedPreferences prefs;
  late String _snapshot = _signature;
  SubtitlePreferences(this.prefs) {
    LanguageController().languageNotifier.addListener(_localeChanged);
  }
  static const followApp = 'app';
  bool get enabled => prefs.getBool('ai_subtitles_enabled') ?? false;
  String get speechModel =>
      prefs.getString('ai_subtitles_speech') ?? 'whisper/small';
  String get translationModel =>
      prefs.getString('ai_subtitles_translation') ?? 'tencent/Hy-MT2-1.8B-GGUF';
  String get sourceLanguage => prefs.getString('ai_subtitles_source') ?? 'auto';
  String get resolvedSourceLanguage {
    final supported = subtitleSourceLanguagesFor(speechModel);
    if (supported.containsKey(sourceLanguage)) return sourceLanguage;
    // A single-language model has no Auto option; use its only language.
    return subtitleModelDetectsLanguage(speechModel)
        ? 'auto'
        : supported.keys.single;
  }

  String get targetLanguage =>
      prefs.getString('ai_subtitles_target') ?? followApp;
  String get resolvedTarget => targetLanguage == followApp
      ? (prefs.getString('selected_language') ??
            LanguageController().currentLocale.languageCode)
      : targetLanguage;

  /// Not part of a session's settings signature: changing it never discards
  /// generated subtitles, it only changes what happens once they are done.
  SubtitleFileMode get fileMode {
    final mode = SubtitleFileMode.values
        .where((m) => m.name == prefs.getString('ai_subtitles_file_mode'))
        .firstOrNull;
    return mode != null && SubtitleFileMode.available.contains(mode)
        ? mode
        : SubtitleFileMode.appOnly;
  }

  Future<void> setFileMode(SubtitleFileMode value) =>
      _set('file_mode', value.name);

  String get _signature =>
      '$enabled|$speechModel|$translationModel|$sourceLanguage|$targetLanguage|$bilingual|$resolvedTarget|${fileMode.name}';

  /// Other desktop windows have their own preference cache.
  Future<void> refresh() async {
    final old = _snapshot;
    await prefs.reload();
    _snapshot = _signature;
    if (old != _snapshot) notifyListeners();
  }

  @override
  void notifyListeners() {
    _snapshot = _signature;
    super.notifyListeners();
  }

  bool get bilingual => prefs.getBool('ai_subtitles_bilingual') ?? false;
  Future<void> setEnabled(bool value) async {
    await prefs.setBool('ai_subtitles_enabled', value);
    notifyListeners();
  }

  Future<void> setSpeechModel(String value) => _set('speech', value);
  Future<void> setTranslationModel(String value) => _set('translation', value);
  Future<void> setSource(String value) => _set('source', value);
  Future<void> setTarget(String value) => _set('target', value);
  Future<void> setBilingual(bool value) async {
    await prefs.setBool('ai_subtitles_bilingual', value);
    notifyListeners();
  }

  Future<void> _set(String key, String value) async {
    await prefs.setString('ai_subtitles_$key', value);
    notifyListeners();
  }

  void _localeChanged() {
    if (targetLanguage == followApp) notifyListeners();
  }

  @override
  void dispose() {
    LanguageController().languageNotifier.removeListener(_localeChanged);
    super.dispose();
  }
}
