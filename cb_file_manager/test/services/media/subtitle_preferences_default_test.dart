import 'package:cb_file_manager/services/media/subtitle_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SubtitlePreferences> load([
    Map<String, Object> values = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(values);
    return SubtitlePreferences.shared(await SharedPreferences.getInstance());
  }

  test('new installs default to Whisper Large v3 Turbo Q5', () async {
    final prefs = await load();
    expect(prefs.speechModel, 'whisper/large-v3-turbo-q5_0');
    await prefs.keepLegacySpeechDefault(const []);
    expect(prefs.speechModel, 'whisper/large-v3-turbo-q5_0');
  });

  test(
    'keeps an installed old default when no model was ever chosen',
    () async {
      final prefs = await load();
      await prefs.keepLegacySpeechDefault(const ['whisper/small']);
      expect(prefs.speechModel, 'whisper/small');
    },
  );

  test(
    'uses Turbo Q5 when it is installed alongside the old default',
    () async {
      final prefs = await load();
      await prefs.keepLegacySpeechDefault(const [
        'whisper/small',
        'whisper/large-v3-turbo-q5_0',
      ]);
      expect(prefs.speechModel, 'whisper/large-v3-turbo-q5_0');
    },
  );

  test('never overrides an explicit choice', () async {
    final prefs = await load({'ai_subtitles_speech': 'whisper/base'});
    await prefs.keepLegacySpeechDefault(const ['whisper/small']);
    expect(prefs.speechModel, 'whisper/base');
  });
}
