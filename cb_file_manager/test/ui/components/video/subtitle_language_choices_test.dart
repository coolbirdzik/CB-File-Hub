import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/services/local_ai/local_ai_advisor_service.dart';
import 'package:cb_file_manager/services/local_ai/local_model_downloads.dart';
import 'package:cb_file_manager/services/media/subtitle_preferences.dart';
import 'package:cb_file_manager/ui/components/video/subtitle_settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late LocalAiAdvisorService models;
  late LocalModelDownloads downloads;
  late SubtitlePreferences preferences;

  Future<void> showPanel(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    preferences = SubtitlePreferences.shared(prefs);
    models = LocalAiAdvisorService(prefs: prefs);
    downloads = LocalModelDownloads(models);
    addTearDown(() async {
      downloads.dispose();
      await models.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi'), Locale('en')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SingleChildScrollView(
            child: SubtitleSettingsPanel(models: models, downloads: downloads),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  DropdownButton<String> field(WidgetTester tester, String key) =>
      tester.widget(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(DropdownButton<String>),
        ),
      );
  List<String> labels(DropdownButton<String> field) =>
      field.items!.map((item) => (item.child as Text).data!).toList();
  void expectAlphabeticalEnglish(List<String> names) {
    expect(
      names,
      orderedEquals(
        [...names]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
      ),
    );
    for (final name in names) {
      expect(RegExp(r'^[A-Za-z ()-]+$').hasMatch(name), isTrue, reason: name);
    }
  }

  testWidgets(
    'audio uses the complete ASR list, in English A–Z even in Vietnamese UI',
    (tester) async {
      await showPanel(tester);
      final audio = field(tester, 'Ngôn ngữ audio:auto');
      expect(audio.items!.length, 100); // Auto + all 99 Base/Small languages.
      expect(labels(audio).first, 'Auto detect');
      expectAlphabeticalEnglish(labels(audio).skip(1).toList());
      expect(
        audio.items!.map((item) => item.value),
        containsAll(['sv', 'cy', 'haw', 'la', 'jw', 'kn']),
      );
      expect(audio.items!.map((item) => item.value), isNot(contains('ug')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('subtitle targets stay English A–Z and independent of ASR', (
    tester,
  ) async {
    await showPanel(tester);
    final target = field(tester, 'Ngôn ngữ phụ đề:app');
    expect(labels(target).first, 'Follow app language');
    expectAlphabeticalEnglish(labels(target).skip(1).toList());
    expect(
      labels(target),
      containsAll([
        'Vietnamese',
        'Chinese (Simplified)',
        'Chinese (Traditional)',
      ]),
    );
    expect(target.items!.map((item) => item.value), contains('ug'));
    expect(target.items!.map((item) => item.value), isNot(contains('sv')));
  });

  testWidgets(
    'Japanese can be found and selected for audio on every speech model',
    (tester) async {
      await showPanel(tester);
      final search = find.byKey(
        const ValueKey('subtitle-language-search:Ngôn ngữ audio'),
      );
      await tester.ensureVisible(search);
      await tester.tap(search);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('subtitle-language-filter')),
        'Japanese',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('subtitle-language-option:ja')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('subtitle-language-option:en')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('subtitle-language-option:ja')),
      );
      await tester.pumpAndSettle();
      for (final model in [
        'whisper/base',
        'whisper/small',
        'whisper/large-v3-turbo',
      ]) {
        await preferences.setSpeechModel(model);
        await tester.pumpAndSettle();
        expect(preferences.sourceLanguage, 'ja');
        expect(preferences.resolvedSourceLanguage, 'ja');
        expect(field(tester, 'Ngôn ngữ audio:ja').value, 'ja');
        expect(
          labels(field(tester, 'Ngôn ngữ audio:ja')),
          contains('Japanese'),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('subtitle language search also finds Japanese by language code', (
    tester,
  ) async {
    await showPanel(tester);
    final search = find.byKey(
      const ValueKey('subtitle-language-search:Ngôn ngữ phụ đề'),
    );
    await tester.ensureVisible(search);
    await tester.tap(search);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('subtitle-language-filter')),
      'ja',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('subtitle-language-option:ja')));
    await tester.pumpAndSettle();
    expect(preferences.resolvedTarget, 'ja');
    expect(field(tester, 'Ngôn ngữ phụ đề:ja').value, 'ja');
  });

  testWidgets(
    'Turbo exposes Cantonese; switching to a 99-language model resolves to Auto',
    (tester) async {
      await showPanel(tester);
      await preferences.setSpeechModel('whisper/large-v3-turbo');
      await tester.pumpAndSettle();
      final audio = field(tester, 'Ngôn ngữ audio:auto');
      expect(audio.items!.length, 101);
      expect(labels(audio), contains('Cantonese'));
      await preferences.setSource('yue');
      await tester.pumpAndSettle();
      expect(field(tester, 'Ngôn ngữ audio:yue').value, 'yue');
      await preferences.setSpeechModel('whisper/base');
      await tester.pumpAndSettle();
      expect(preferences.resolvedSourceLanguage, 'auto');
      expect(field(tester, 'Ngôn ngữ audio:auto').value, 'auto');
      expect(tester.takeException(), isNull);
    },
  );
}
