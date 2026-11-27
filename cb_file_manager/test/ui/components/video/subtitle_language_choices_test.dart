import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/config/theme_config.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/models/local_ai/local_ai_advisor_model.dart';
import 'package:cb_file_manager/services/local_ai/local_ai_advisor_service.dart';
import 'package:cb_file_manager/services/local_ai/local_model_downloads.dart';
import 'package:cb_file_manager/services/local_ai/subtitle_model_catalog.dart';
import 'package:cb_file_manager/services/media/subtitle_preferences.dart';
import 'package:cb_file_manager/ui/components/video/subtitle_settings_panel.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations, GlobalCupertinoLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late LocalAiAdvisorService models;
  late LocalModelDownloads downloads;
  late SubtitlePreferences preferences;

  Future<void> showPanel(
    WidgetTester tester, {
    bool compact = false,
    VoidCallback? onManageModels,
  }) async {
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
        theme: ThemeConfig.getLightTheme(),
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi'), Locale('en')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: onManageModels == null
              ? SingleChildScrollView(
                  child: SubtitleSettingsPanel(
                    models: models,
                    downloads: downloads,
                    compact: compact,
                  ),
                )
              : Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => SubtitleSettingsDialog(
                        models: models,
                        downloads: downloads,
                        preferences: preferences,
                        onManageModels: (_) => onManageModels(),
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (onManageModels != null) {
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }
  }

  CbSelect<String> field(WidgetTester tester, String key) =>
      tester.widget(find.byKey(ValueKey(key)));
  List<String> labels(CbSelect<String> field) =>
      field.items.map((item) => item.label).toList();
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
      expect(audio.items.length, 100); // Auto + all 99 Base/Small languages.
      expect(labels(audio).first, 'Auto detect');
      expectAlphabeticalEnglish(labels(audio).skip(1).toList());
      expect(
        audio.items.map((item) => item.value),
        containsAll(['sv', 'cy', 'haw', 'la', 'jw', 'kn']),
      );
      expect(audio.items.map((item) => item.value), isNot(contains('ug')));
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
    expect(target.items.map((item) => item.value), contains('ug'));
    expect(target.items.map((item) => item.value), isNot(contains('sv')));
  });

  testWidgets(
    'Japanese can be found and selected for audio on every speech model',
    (tester) async {
      await showPanel(tester);
      final select = find.byKey(const ValueKey('Ngôn ngữ audio:auto'));
      await tester.ensureVisible(select);
      await tester.tap(select);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Japanese');
      await tester.pumpAndSettle();
      expect(find.text('Japanese'), findsWidgets);
      expect(find.text('English'), findsNothing);
      await tester.tap(find.text('Japanese').last);
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
    final select = find.byKey(const ValueKey('Ngôn ngữ phụ đề:app'));
    await tester.ensureVisible(select);
    await tester.tap(select);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ja');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Japanese').last);
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
      expect(audio.items.length, 101);
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

  testWidgets(
    'a Japanese-only speech model hides Auto and resolves the source to ja',
    (tester) async {
      await showPanel(tester);
      expect(preferences.sourceLanguage, 'auto');
      await preferences.setSpeechModel('whisper/kotoba-v2.0-q5_0');
      await tester.pumpAndSettle();
      expect(preferences.resolvedSourceLanguage, 'ja');
      final audio = field(tester, 'Ngôn ngữ audio:ja');
      expect(audio.value, 'ja');
      expect(labels(audio), ['Japanese']);
      // Switching back restores automatic detection of the stored 'auto'.
      await preferences.setSpeechModel('whisper/small');
      await tester.pumpAndSettle();
      expect(preferences.resolvedSourceLanguage, 'auto');
      expect(labels(field(tester, 'Ngôn ngữ audio:auto')).first, 'Auto detect');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('every catalog model can be selected without layout errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(520, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await showPanel(tester);
    for (final purpose in [
      LocalModelPurpose.speech,
      LocalModelPurpose.translation,
    ]) {
      for (final entry in SubtitleModelCatalog.forPurpose(purpose)) {
        await (purpose == LocalModelPurpose.speech
            ? preferences.setSpeechModel(entry.id)
            : preferences.setTranslationModel(entry.id));
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('subtitle-model-install:${entry.id}')),
          findsOneWidget,
        );
        expect(find.text(entry.description!), findsOneWidget);
        expect(tester.takeException(), isNull, reason: entry.id);
      }
    }
  });

  testWidgets('open model menus list every model with its size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(520, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await showPanel(tester);
    for (final (purpose, selected) in [
      (LocalModelPurpose.speech, preferences.speechModel),
      (LocalModelPurpose.translation, preferences.translationModel),
    ]) {
      await tester.tap(
        find.byKey(ValueKey('subtitle-model:${purpose.name}:$selected')),
      );
      await tester.pumpAndSettle();
      for (final entry in SubtitleModelCatalog.forPurpose(purpose)) {
        expect(
          find.textContaining(entry.displayName),
          findsWidgets,
          reason: entry.id,
        );
      }
      expect(
        find.textContaining('574 MB'),
        purpose == LocalModelPurpose.speech ? findsWidgets : findsNothing,
      );
      expect(tester.takeException(), isNull, reason: purpose.name);
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('subtitle file mode defaults to app-only and can be changed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(520, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await showPanel(tester);
    String hint() => tester
        .widget<Text>(find.byKey(const ValueKey('ai-subtitle-file-mode-hint')))
        .data!;
    expect(preferences.fileMode, SubtitleFileMode.appOnly);
    expect(hint(), contains('Không tạo file nào'));
    final dropdown = find.byKey(
      const ValueKey('ai-subtitle-file-mode:appOnly'),
    );
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tự lưu vào thư mục Subs').last);
    await tester.pumpAndSettle();
    expect(preferences.fileMode, SubtitleFileMode.subsFolder);
    expect(hint(), contains('Subs/'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the compact CC panel shows core controls and folds files away', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await showPanel(tester, compact: true);

    expect(find.text('Phụ đề AI local'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-subtitles-enabled')), findsOneWidget);
    expect(field(tester, 'Ngôn ngữ audio:auto').value, 'auto');
    expect(
      find.byKey(ValueKey('subtitle-model-install:${preferences.speechModel}')),
      findsOneWidget,
    );
    final model = models.catalogEntryFor(preferences.speechModel)!;
    expect(find.text(model.description!), findsNothing);

    final files = find.text('File phụ đề');
    final fileMode = find.byKey(
      const ValueKey('ai-subtitle-file-mode:appOnly'),
    );
    expect(fileMode, findsNothing);
    await tester.ensureVisible(files);
    await tester.tap(files);
    await tester.pumpAndSettle();
    expect(fileMode, findsOneWidget);
    expect(
      find.byKey(const ValueKey('ai-subtitle-clear-cache')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the CC dialog aligns and outlines its actions', (tester) async {
    tester.view.physicalSize = const Size(420, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var opened = 0;
    await showPanel(tester, onManageModels: () => opened++);

    expect(find.byType(CbDialog), findsOneWidget);
    final title = find.text('Phụ đề AI local');
    expect(title, findsOneWidget);
    final enabled = find.byKey(const ValueKey('ai-subtitles-enabled'));
    final manage = find.byKey(const ValueKey('ai-subtitles-manage-models'));
    final close = find.widgetWithText(CbButton, 'Đóng');
    expect(tester.widget<CbButton>(manage).outlined, isTrue);
    expect(tester.widget<CbButton>(close).outlined, isTrue);
    expect(tester.getCenter(manage).dy, tester.getCenter(close).dy);

    final wasEnabled = preferences.enabled;
    await tester.tap(enabled);
    await tester.pumpAndSettle();
    expect(preferences.enabled, !wasEnabled);
    await tester.tap(manage);
    expect(opened, 1);

    final files = find.text('File phụ đề');
    await tester.ensureVisible(files);
    await tester.tap(files);
    await tester.pumpAndSettle();
    final fileHeader = find.ancestor(
      of: files,
      matching: find.byType(ListTile),
    );
    final fileMode = find.byKey(
      const ValueKey('ai-subtitle-file-mode:appOnly'),
    );
    expect(
      tester.getTopLeft(fileMode).dy - tester.getBottomLeft(fileHeader).dy,
      greaterThanOrEqualTo(CbSpacing.sm),
    );
    final fileHint = find.byKey(const ValueKey('ai-subtitle-file-mode-hint'));
    final cacheTitle = find.text('Cache phụ đề');
    expect(
      tester.getTopLeft(cacheTitle).dy - tester.getBottomLeft(fileHint).dy,
      greaterThanOrEqualTo(CbSpacing.md),
    );
    final clear = find.byKey(const ValueKey('ai-subtitle-clear-cache'));
    await tester.ensureVisible(clear);
    expect(tester.widget<CbButton>(clear).outlined, isTrue);
    expect(tester.getTopLeft(clear).dx, tester.getTopLeft(title).dx);

    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.byType(SubtitleSettingsDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide panels place audio and subtitle languages side by side', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await showPanel(tester);
    final source = tester.getTopLeft(
      find.byKey(const ValueKey('Ngôn ngữ audio:auto')),
    );
    final target = tester.getTopLeft(
      find.byKey(const ValueKey('Ngôn ngữ phụ đề:app')),
    );
    expect(source.dy, target.dy);
    expect(target.dx, greaterThan(source.dx));
    expect(tester.takeException(), isNull);
  });
}
