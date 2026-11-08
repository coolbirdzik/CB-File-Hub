import 'package:cb_file_manager/models/local_ai/local_ai_advisor_model.dart';
import 'package:cb_file_manager/services/local_ai/local_ai_advisor_service.dart';
import 'package:cb_file_manager/services/local_ai/subtitle_model_catalog.dart';
import 'package:cb_file_manager/services/media/subtitle_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const entries = SubtitleModelCatalog.entries;

  test('IDs are unique, path-safe and each artifact is pinned', () {
    expect(entries.map((e) => e.id).toSet().length, entries.length);
    for (final entry in entries) {
      // The ID becomes a storage folder name with '/' replaced by '_'.
      expect(entry.id, matches(RegExp(r'^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$')));
      expect(
        entry.sha256,
        matches(RegExp(r'^[0-9a-f]{64}$')),
        reason: entry.id,
      );
      expect(entry.sizeBytes, greaterThan(0), reason: entry.id);
      expect(entry.license, isNotNull, reason: entry.id);
      expect(entry.description, isNotNull, reason: entry.id);
      expect(
        entry.purpose,
        isIn([LocalModelPurpose.speech, LocalModelPurpose.translation]),
      );
      final file = entry.artifactFileName;
      expect(
        entry.purpose == LocalModelPurpose.speech
            ? file.endsWith('.bin')
            : file.endsWith('.gguf'),
        isTrue,
        reason: entry.id,
      );
    }
  });

  test(
    'profiles cover exactly the catalog, one recommendation per purpose',
    () {
      expect(
        SubtitleModelCatalog.profiles.keys.toSet(),
        entries.map((e) => e.id).toSet(),
      );
      for (final purpose in [
        LocalModelPurpose.speech,
        LocalModelPurpose.translation,
      ]) {
        expect(
          SubtitleModelCatalog.forPurpose(
            purpose,
          ).where((e) => SubtitleModelCatalog.profiles[e.id]!.recommended),
          hasLength(1),
          reason: purpose.name,
        );
      }
    },
  );

  test('translation IDs keep the translation sampling prefix', () {
    for (final entry in SubtitleModelCatalog.forPurpose(
      LocalModelPurpose.translation,
    )) {
      expect(
        entry.id.split('/').last.toLowerCase(),
        startsWith('hy-mt'),
        reason: entry.id,
      );
    }
  });

  test(
    'preference defaults and service lookups resolve to these entries',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final preferences = SubtitlePreferences(prefs);
      addTearDown(preferences.dispose);
      final service = LocalAiAdvisorService(prefs: prefs);
      addTearDown(service.dispose);
      expect(SubtitleModelCatalog.profiles, contains(preferences.speechModel));
      expect(
        SubtitleModelCatalog.profiles,
        contains(preferences.translationModel),
      );
      for (final entry in entries) {
        // A chat catalog entry with the same ID would shadow this one.
        expect(service.catalogEntryFor(entry.id)?.purpose, entry.purpose);
      }
    },
  );

  test('source languages follow each speech model', () {
    expect(subtitleSourceLanguagesFor('whisper/tiny'), hasLength(99));
    expect(subtitleSourceLanguagesFor('whisper/small'), isNot(contains('yue')));
    expect(
      subtitleSourceLanguagesFor('whisper/large-v3-turbo-q5_0'),
      contains('yue'),
    );
    expect(subtitleSourceLanguagesFor('whisper/large-v3-q5_0'), hasLength(100));
    expect(subtitleSourceLanguagesFor('whisper/kotoba-v2.0-q5_0'), {
      'ja': 'Japanese',
    });
    expect(subtitleModelDetectsLanguage('whisper/kotoba-v2.0-q5_0'), isFalse);
    expect(subtitleModelDetectsLanguage('whisper/small'), isTrue);
  });
}
