import '../local_ai/subtitle_model_catalog.dart';

/// Language codes match the pinned whisper.cpp 1.9.5 language table.
/// Labels stay English independently of the application UI locale.
final subtitleSourceLanguages = _alphabetical({
  'af': 'Afrikaans',
  'sq': 'Albanian',
  'am': 'Amharic',
  'ar': 'Arabic',
  'hy': 'Armenian',
  'as': 'Assamese',
  'az': 'Azerbaijani',
  'ba': 'Bashkir',
  'eu': 'Basque',
  'be': 'Belarusian',
  'bn': 'Bengali',
  'bs': 'Bosnian',
  'br': 'Breton',
  'bg': 'Bulgarian',
  'my': 'Burmese',
  'yue': 'Cantonese',
  'ca': 'Catalan',
  'zh': 'Chinese',
  'hr': 'Croatian',
  'cs': 'Czech',
  'da': 'Danish',
  'nl': 'Dutch',
  'en': 'English',
  'et': 'Estonian',
  'fo': 'Faroese',
  'tl': 'Filipino (Tagalog)',
  'fi': 'Finnish',
  'fr': 'French',
  'gl': 'Galician',
  'ka': 'Georgian',
  'de': 'German',
  'el': 'Greek',
  'gu': 'Gujarati',
  'ht': 'Haitian Creole',
  'ha': 'Hausa',
  'haw': 'Hawaiian',
  'he': 'Hebrew',
  'hi': 'Hindi',
  'hu': 'Hungarian',
  'is': 'Icelandic',
  'id': 'Indonesian',
  'it': 'Italian',
  'ja': 'Japanese',
  'jw': 'Javanese',
  'kn': 'Kannada',
  'kk': 'Kazakh',
  'km': 'Khmer',
  'ko': 'Korean',
  'lo': 'Lao',
  'la': 'Latin',
  'lv': 'Latvian',
  'ln': 'Lingala',
  'lt': 'Lithuanian',
  'lb': 'Luxembourgish',
  'mk': 'Macedonian',
  'mg': 'Malagasy',
  'ms': 'Malay',
  'ml': 'Malayalam',
  'mt': 'Maltese',
  'mi': 'Maori',
  'mr': 'Marathi',
  'mn': 'Mongolian',
  'ne': 'Nepali',
  'no': 'Norwegian',
  'nn': 'Norwegian Nynorsk',
  'oc': 'Occitan',
  'ps': 'Pashto',
  'fa': 'Persian',
  'pl': 'Polish',
  'pt': 'Portuguese',
  'pa': 'Punjabi',
  'ro': 'Romanian',
  'ru': 'Russian',
  'sa': 'Sanskrit',
  'sr': 'Serbian',
  'sn': 'Shona',
  'sd': 'Sindhi',
  'si': 'Sinhala',
  'sk': 'Slovak',
  'sl': 'Slovenian',
  'so': 'Somali',
  'es': 'Spanish',
  'su': 'Sundanese',
  'sw': 'Swahili',
  'sv': 'Swedish',
  'tg': 'Tajik',
  'ta': 'Tamil',
  'tt': 'Tatar',
  'te': 'Telugu',
  'th': 'Thai',
  'bo': 'Tibetan',
  'tr': 'Turkish',
  'tk': 'Turkmen',
  'uk': 'Ukrainian',
  'ur': 'Urdu',
  'uz': 'Uzbek',
  'vi': 'Vietnamese',
  'cy': 'Welsh',
  'yi': 'Yiddish',
  'yo': 'Yoruba',
});

final _legacyWhisperLanguages = Map<String, String>.unmodifiable({
  for (final entry in subtitleSourceLanguages.entries)
    if (entry.key != 'yue') entry.key: entry.value,
});

/// Whisper v1/v2-era models have 99 language tokens; v3 adds Cantonese.
/// Single-language fine-tunes accept only their own language. Unknown IDs keep
/// the complete list.
Map<String, String> subtitleSourceLanguagesFor(String modelId) {
  final profile = SubtitleModelCatalog.profiles[modelId];
  if (profile == null) return subtitleSourceLanguages;
  final only = profile.onlyLanguage;
  if (only != null) {
    return Map.unmodifiable({only: subtitleSourceLanguages[only] ?? only});
  }
  return profile.cantonese ? subtitleSourceLanguages : _legacyWhisperLanguages;
}

/// Whether the speech model can detect the audio language by itself.
bool subtitleModelDetectsLanguage(String modelId) =>
    SubtitleModelCatalog.profiles[modelId]?.onlyLanguage == null;

/// Translation targets are independent of the larger ASR language list.
final subtitleTargetLanguages = _alphabetical({
  'ar': 'Arabic',
  'bn': 'Bengali',
  'my': 'Burmese',
  'yue': 'Cantonese',
  'zh': 'Chinese (Simplified)',
  'zh-Hant': 'Chinese (Traditional)',
  'cs': 'Czech',
  'nl': 'Dutch',
  'en': 'English',
  'tl': 'Filipino (Tagalog)',
  'fr': 'French',
  'de': 'German',
  'gu': 'Gujarati',
  'he': 'Hebrew',
  'hi': 'Hindi',
  'id': 'Indonesian',
  'it': 'Italian',
  'ja': 'Japanese',
  'kk': 'Kazakh',
  'km': 'Khmer',
  'ko': 'Korean',
  'ms': 'Malay',
  'mr': 'Marathi',
  'mn': 'Mongolian',
  'fa': 'Persian',
  'pl': 'Polish',
  'pt': 'Portuguese',
  'ru': 'Russian',
  'es': 'Spanish',
  'ta': 'Tamil',
  'te': 'Telugu',
  'th': 'Thai',
  'bo': 'Tibetan',
  'tr': 'Turkish',
  'uk': 'Ukrainian',
  'ur': 'Urdu',
  'ug': 'Uyghur',
  'vi': 'Vietnamese',
});

String subtitleLanguageEnglishName(String code) =>
    subtitleTargetLanguages[code] ?? subtitleSourceLanguages[code] ?? code;

Map<String, String> _alphabetical(Map<String, String> languages) {
  final entries = languages.entries.toList()
    ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
  return Map<String, String>.unmodifiable(Map.fromEntries(entries));
}
