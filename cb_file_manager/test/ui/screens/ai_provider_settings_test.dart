import 'dart:async';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/design_system/primitives/cb_select.dart';
import 'package:cb_file_manager/models/ai/ai_provider_model.dart';
import 'package:cb_file_manager/services/ai/ai_provider_service.dart';
import 'package:cb_file_manager/ui/screens/settings/ai_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

AiProviderConfig config({
  AiApiType apiType = AiApiType.openaiCompatible,
  AiProviderAuthMode authMode = AiProviderAuthMode.apiKey,
  String endpoint = 'https://custom.example/v1',
}) => AiProviderConfig(
  id: 'existing',
  name: 'My provider',
  apiType: apiType,
  authMode: authMode,
  apiKey: 'saved-key',
  endpoint: endpoint,
  modelName: 'saved-model',
  createdAt: 1,
  updatedAt: 1,
);

class _Providers extends AiProviderService {
  List<AiProviderConfig> providers = [];
  AiProviderConfig? saved;
  Completer<List<String>>? models;
  List<String> modelList = ['test-codex-model', 'saved-model'];
  int modelRequests = 0;
  Object? modelsError;

  @override
  Future<List<AiProviderConfig>> getProviders() async => providers;

  @override
  Future<AiProviderConfig> addProvider({
    required String name,
    required AiApiType apiType,
    AiProviderAuthMode authMode = AiProviderAuthMode.apiKey,
    required String apiKey,
    required String endpoint,
    required String modelName,
    double temperature = .3,
    int maxTokens = 4096,
    String? systemPrompt,
    int timeoutSeconds = 30,
    int maxRetries = 2,
    int priority = 0,
  }) async => saved = AiProviderConfig(
    id: 'new',
    name: name,
    apiType: apiType,
    authMode: authMode,
    apiKey: apiKey,
    endpoint: endpoint,
    modelName: modelName,
    createdAt: 1,
    updatedAt: 1,
  );

  @override
  Future<void> updateProvider(AiProviderConfig config) async {
    saved = config;
  }

  @override
  Future<List<String>> fetchModels({
    required AiApiType apiType,
    AiProviderAuthMode authMode = AiProviderAuthMode.apiKey,
    required String apiKey,
    required String endpoint,
  }) {
    modelRequests++;
    if (modelsError != null) return Future.error(modelsError!);
    return models?.future ?? Future.value(modelList);
  }
}

void main() {
  late _Providers providers;
  setUp(() {
    providers = _Providers();
    GetIt.instance.registerSingleton<AiProviderService>(providers);
  });
  tearDown(() async {
    await GetIt.instance.unregister<AiProviderService>();
    providers.dispose();
  });

  Future<void> mount(WidgetTester tester, {bool edit = false}) async {
    tester.view.physicalSize = const Size(1100, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizationsDelegate()],
        home: Scaffold(
          body: SingleChildScrollView(
            child: AiSettingsSection(
              buildSectionCard:
                  ({required title, required icon, required children}) =>
                      Column(children: children),
              buildCompactSettingTile:
                  ({
                    required title,
                    required subtitle,
                    required icon,
                    trailing,
                    onTap,
                  }) => ListTile(
                    title: Text(title),
                    subtitle: Text(subtitle),
                    trailing: trailing,
                    onTap: onTap,
                  ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (edit) {
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
    } else {
      await tester.tap(find.text('Add Provider'));
    }
    await tester.pumpAndSettle();
  }

  Future<void> selectKind(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.byKey(const ValueKey('ai-provider-kind')));
    await tester.tap(find.byKey(const ValueKey('ai-provider-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String field, String text) async {
    final finder = find.byKey(ValueKey('ai-provider-$field'));
    await tester.ensureVisible(finder);
    await tester.enterText(finder, text);
    await tester.pump();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> chooseModel(WidgetTester tester, String model) async {
    final picker = find.byKey(const ValueKey('ai-provider-model-select'));
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text(model).last);
    await tester.pumpAndSettle();
  }

  testWidgets('Codex is a provider type and saves OAuth without an API key', (
    tester,
  ) async {
    await mount(tester);
    await selectKind(tester, 'Codex');
    expect(find.byType(SegmentedButton<AiApiType>), findsNothing);
    expect(find.byType(SegmentedButton<AiProviderAuthMode>), findsNothing);
    expect(find.byKey(const ValueKey('ai-provider-api-key')), findsNothing);
    expect(find.byKey(const ValueKey('ai-provider-endpoint')), findsNothing);
    expect(providers.modelRequests, 1);
    expect(find.byKey(const ValueKey('ai-provider-model')), findsNothing);
    await chooseModel(tester, 'test-codex-model');
    await save(tester);
    expect(providers.saved!.name, 'Codex');
    expect(providers.saved!.authMode, AiProviderAuthMode.codexOAuth);
    expect(providers.saved!.apiKey, isEmpty);
    expect(providers.saved!.apiType, AiApiType.openaiCompatible);
    expect(providers.saved!.modelName, 'test-codex-model');
  });

  testWidgets('Codex requires an explicit selection from its model list', (
    tester,
  ) async {
    await mount(tester);
    await selectKind(tester, 'Codex');
    await save(tester);
    expect(providers.saved, isNull);
    expect(find.byKey(const ValueKey('ai-provider-model')), findsNothing);
    expect(
      tester
          .widget<CbSelect<String>>(
            find.byKey(const ValueKey('ai-provider-model-select')),
          )
          .errorText,
      'Select a model',
    );
  });

  testWidgets(
    'Codex stays a picker when its model list is empty and can retry',
    (tester) async {
      providers.modelList = [];
      await mount(tester);
      await selectKind(tester, 'Codex');
      expect(find.text('No models found'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-provider-model')), findsNothing);
      await save(tester);
      expect(providers.saved, isNull);
      providers.modelList = ['retry-model'];
      await tester.tap(find.byTooltip('Fetch Models'));
      await tester.pumpAndSettle();
      await chooseModel(tester, 'retry-model');
      await save(tester);
      expect(providers.saved!.modelName, 'retry-model');
    },
  );

  testWidgets('Codex refresh removes a selection no longer in its model list', (
    tester,
  ) async {
    await mount(tester);
    await selectKind(tester, 'Codex');
    await chooseModel(tester, 'test-codex-model');
    providers.modelList = ['replacement-model'];
    await tester.tap(find.byTooltip('Fetch Models'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CbSelect<String>>(
            find.byKey(const ValueKey('ai-provider-model-select')),
          )
          .value,
      isNull,
    );
    await save(tester);
    expect(providers.saved, isNull);
    await chooseModel(tester, 'replacement-model');
    await save(tester);
    expect(providers.saved!.modelName, 'replacement-model');
  });

  testWidgets(
    'Codex loading disables saving and ignores a response after changing type',
    (tester) async {
      await mount(tester);
      providers.models = Completer<List<String>>();
      await tester.tap(find.byKey(const ValueKey('ai-provider-kind')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Codex').last);
      await tester.pump(const Duration(milliseconds: 300));
      expect(providers.modelRequests, 1);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull,
      );
      expect(find.byKey(const ValueKey('ai-provider-model')), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('ai-provider-kind')),
      );
      await tester.tap(find.byKey(const ValueKey('ai-provider-kind')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Custom').last);
      await tester.pumpAndSettle();
      providers.models!.complete(['old-codex-model']);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-provider-model')), findsOneWidget);
      expect(find.text('old-codex-model'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Codex discovery failure keeps a picker and allows retry', (
    tester,
  ) async {
    providers.modelsError = StateError('model cache unavailable');
    await mount(tester);
    await selectKind(tester, 'Codex');
    expect(find.textContaining('model cache unavailable'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-provider-model')), findsNothing);
    await save(tester);
    expect(providers.saved, isNull);
    providers.modelsError = null;
    await tester.tap(find.byTooltip('Fetch Models'));
    await tester.pumpAndSettle();
    await chooseModel(tester, 'test-codex-model');
    await save(tester);
    expect(providers.saved!.modelName, 'test-codex-model');
  });

  testWidgets('editing Codex rejects an old model absent from the list', (
    tester,
  ) async {
    providers.providers = [config(authMode: AiProviderAuthMode.codexOAuth)];
    providers.modelList = ['current-model'];
    await mount(tester, edit: true);
    expect(providers.modelRequests, 1);
    expect(find.byKey(const ValueKey('ai-provider-model')), findsNothing);
    await save(tester);
    expect(providers.saved, isNull);
    await chooseModel(tester, 'current-model');
    await save(tester);
    expect(providers.saved!.modelName, 'current-model');
  });

  testWidgets(
    'Codex refresh retains a valid selection and deduplicates models',
    (tester) async {
      await mount(tester);
      await selectKind(tester, 'Codex');
      await chooseModel(tester, 'test-codex-model');
      providers.modelList = [
        'test-codex-model',
        'test-codex-model',
        '  ',
        'second-model',
      ];
      await tester.tap(find.byTooltip('Fetch Models'));
      await tester.pumpAndSettle();
      final picker = tester.widget<CbSelect<String>>(
        find.byKey(const ValueKey('ai-provider-model-select')),
      );
      expect(picker.value, 'test-codex-model');
      expect(picker.items.map((item) => item.value), [
        'test-codex-model',
        'second-model',
      ]);
      await save(tester);
      expect(providers.saved!.modelName, 'test-codex-model');
    },
  );

  testWidgets('Claude owns the Anthropic protocol and endpoint', (
    tester,
  ) async {
    await mount(tester);
    await selectKind(tester, 'Claude');
    expect(find.byType(SegmentedButton<AiApiType>), findsNothing);
    expect(find.byKey(const ValueKey('ai-provider-endpoint')), findsNothing);
    await enter(tester, 'api-key', 'claude-test-key');
    await enter(tester, 'model', 'test-claude-model');
    await save(tester);
    expect(providers.saved!.name, 'Claude');
    expect(providers.saved!.apiType, AiApiType.anthropic);
    expect(providers.saved!.authMode, AiProviderAuthMode.apiKey);
    expect(
      providers.saved!.endpoint,
      AiProviderConfig.defaultEndpoint(AiApiType.anthropic),
    );
  });

  testWidgets('Custom accepts other endpoints with either protocol', (
    tester,
  ) async {
    await mount(tester);
    expect(find.byType(SegmentedButton<AiApiType>), findsOneWidget);
    await tester.tap(find.text('Anthropic'));
    await tester.pump();
    await enter(tester, 'name', 'My gateway');
    await enter(tester, 'api-key', 'custom-test-key');
    await enter(tester, 'endpoint', 'https://custom.example/messages');
    await enter(tester, 'model', 'custom-model');
    await save(tester);
    expect(providers.saved!.endpoint, 'https://custom.example/messages');
    expect(providers.saved!.apiType, AiApiType.anthropic);
    expect(providers.saved!.authMode, AiProviderAuthMode.apiKey);
  });

  testWidgets('switching from Codex to Custom saves an API provider', (
    tester,
  ) async {
    await mount(tester);
    await selectKind(tester, 'Codex');
    await selectKind(tester, 'Custom');
    expect(find.byKey(const ValueKey('ai-provider-api-key')), findsOneWidget);
    expect(find.byType(SegmentedButton<AiApiType>), findsOneWidget);
    await enter(tester, 'name', 'My OpenAI compatible API');
    await enter(tester, 'api-key', 'test-key');
    await enter(tester, 'endpoint', 'https://api.example/v1');
    await enter(tester, 'model', 'my-model');
    await save(tester);
    expect(providers.saved!.apiType, AiApiType.openaiCompatible);
    expect(providers.saved!.authMode, AiProviderAuthMode.apiKey);
    expect(providers.saved!.endpoint, 'https://api.example/v1');
  });

  testWidgets('changing provider type discards a late model discovery result', (
    tester,
  ) async {
    providers.models = Completer<List<String>>();
    await mount(tester);
    await selectKind(tester, 'Claude');
    await enter(tester, 'api-key', 'test-key');
    await tester.tap(find.byTooltip('Fetch Models'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('ai-provider-kind')));
    await tester.tap(find.byKey(const ValueKey('ai-provider-kind')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Custom').last);
    await tester.pumpAndSettle();
    providers.models!.complete(['model-from-old-provider']);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-provider-model')), findsOneWidget);
    expect(find.text('model-from-old-provider'), findsNothing);
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('ai-provider-api-key')),
          )
          .controller!
          .text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'editing an existing custom Anthropic gateway preserves its configuration',
    (tester) async {
      final original = config(apiType: AiApiType.anthropic);
      providers.providers = [original];
      await mount(tester, edit: true);
      expect(find.byType(SegmentedButton<AiApiType>), findsOneWidget);
      await save(tester);
      expect(providers.saved!.endpoint, original.endpoint);
      expect(providers.saved!.apiKey, original.apiKey);
      expect(providers.saved!.modelName, original.modelName);
      expect(providers.saved!.id, original.id);
    },
  );

  for (final codex in [false, true]) {
    testWidgets('existing built-in type is selected on edit (Codex: $codex)', (
      tester,
    ) async {
      providers.providers = [
        config(
          apiType: codex ? AiApiType.openaiCompatible : AiApiType.anthropic,
          authMode: codex
              ? AiProviderAuthMode.codexOAuth
              : AiProviderAuthMode.apiKey,
          endpoint: AiProviderConfig.defaultEndpoint(
            codex ? AiApiType.openaiCompatible : AiApiType.anthropic,
          ),
        ),
      ];
      await mount(tester, edit: true);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('ai-provider-kind')),
          matching: find.text(codex ? 'Codex' : 'Claude'),
        ),
        findsOneWidget,
      );
      await save(tester);
      expect(providers.saved!.modelName, 'saved-model');
    });
  }
}
