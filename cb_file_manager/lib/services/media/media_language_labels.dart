import 'subtitle_languages.dart';

/// Container tags commonly use ISO 639-2 while speech models use ISO 639-1.
/// Display English names regardless of the UI locale or a native track title.
String? mediaLanguageEnglishName(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final normalized = value.trim().toLowerCase().replaceAll('_', '-');
  if (normalized == 'zh-hant' ||
      normalized == 'zh-tw' ||
      normalized == 'zh-hk') {
    return 'Chinese (Traditional)';
  }
  final base = normalized.split('-').first;
  final code = _iso6392[base] ?? base;
  final name = subtitleSourceLanguages[code] ?? subtitleTargetLanguages[code];
  if (name != null) return name;
  for (final label in {
    ...subtitleSourceLanguages,
    ...subtitleTargetLanguages,
  }.values) {
    if (label.toLowerCase() == normalized) return label;
  }
  for (final entry in _nativeNames.entries) {
    if (normalized.contains(entry.key)) return entry.value;
  }
  return null;
}

const _nativeNames = {
  '日本語': 'Japanese',
  'にほんご': 'Japanese',
  '中文': 'Chinese',
  '汉语': 'Chinese',
  '漢語': 'Chinese',
  '普通话': 'Chinese',
  '普通話': 'Chinese',
  '粤语': 'Cantonese',
  '粵語': 'Cantonese',
  '한국어': 'Korean',
  '조선말': 'Korean',
  'tiếng việt': 'Vietnamese',
};

const _iso6392 = {
  'afr': 'af', 'amh': 'am', 'ara': 'ar', 'asm': 'as', 'aze': 'az',
  'bak': 'ba', 'bel': 'be', 'ben': 'bn', 'bod': 'bo', 'bos': 'bs',
  'bre': 'br', 'bul': 'bg', 'cat': 'ca', 'ces': 'cs', 'cym': 'cy',
  'dan': 'da', 'deu': 'de', 'ell': 'el', 'eng': 'en', 'est': 'et',
  'eus': 'eu', 'fao': 'fo', 'fas': 'fa', 'fin': 'fi', 'fra': 'fr',
  'glg': 'gl', 'guj': 'gu', 'hat': 'ht', 'hau': 'ha', 'heb': 'he',
  'hin': 'hi', 'hrv': 'hr', 'hun': 'hu', 'hye': 'hy', 'ind': 'id',
  'isl': 'is', 'ita': 'it', 'jav': 'jw', 'jpn': 'ja', 'kan': 'kn',
  'kat': 'ka', 'kaz': 'kk', 'khm': 'km', 'kor': 'ko', 'lao': 'lo',
  'lat': 'la', 'lav': 'lv', 'lin': 'ln', 'lit': 'lt', 'ltz': 'lb',
  'mal': 'ml', 'mar': 'mr', 'mkd': 'mk', 'mlg': 'mg', 'mlt': 'mt',
  'mon': 'mn', 'mri': 'mi', 'msa': 'ms', 'mya': 'my', 'nep': 'ne',
  'nld': 'nl', 'nno': 'nn', 'nor': 'no', 'nob': 'no', 'oci': 'oc',
  'pan': 'pa', 'pol': 'pl', 'por': 'pt', 'pus': 'ps', 'ron': 'ro',
  'rus': 'ru', 'san': 'sa', 'sin': 'si', 'slk': 'sk', 'slv': 'sl',
  'sna': 'sn', 'snd': 'sd', 'som': 'so', 'spa': 'es', 'sqi': 'sq',
  'srp': 'sr', 'sun': 'su', 'swa': 'sw', 'swe': 'sv', 'tam': 'ta',
  'tat': 'tt', 'tel': 'te', 'tgk': 'tg', 'tha': 'th', 'tuk': 'tk',
  'tur': 'tr', 'uig': 'ug', 'ukr': 'uk', 'urd': 'ur', 'uzb': 'uz',
  'vie': 'vi', 'yid': 'yi', 'yor': 'yo', 'zho': 'zh', 'fil': 'tl',
  // Bibliographic variants still found in older media containers.
  'alb': 'sq', 'arm': 'hy', 'baq': 'eu', 'bur': 'my', 'chi': 'zh',
  'cze': 'cs', 'dut': 'nl', 'fre': 'fr', 'geo': 'ka', 'ger': 'de',
  'gre': 'el', 'ice': 'is', 'mac': 'mk', 'mao': 'mi', 'may': 'ms',
  'per': 'fa', 'rum': 'ro', 'slo': 'sk', 'tib': 'bo', 'wel': 'cy',
};
