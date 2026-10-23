import 'dart:async';
import 'dart:convert';

import 'package:cb_file_manager/bloc/ai_agent/ai_agent.dart';
import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/models/ai/ai_provider_model.dart';
import 'package:cb_file_manager/models/local_ai/local_ai_advisor_model.dart';
import 'package:cb_file_manager/services/ai/ai_provider_service.dart';
import 'package:cb_file_manager/services/local_ai/local_ai_advisor_service.dart';
import 'package:cb_file_manager/ui/screens/ai_chat/components/local_model_guide_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _installedModelsKey = 'local_ai_installed_models';

final _installedModel = InstalledLocalModel(
  catalogId: 'org/tiny-gguf',
  displayName: 'Tiny',
  localPath: '/models/tiny.gguf',
  sizeBytes: 1,
  installedAt: DateTime(2026),
  runtimeArtifactId: 'tiny.gguf',
);

Future<LocalAiAdvisorService> _registerLocalAi({
  List<InstalledLocalModel> installed = const [],
}) async {
  final prefs = await SharedPreferences.getInstance();
  if (installed.isEmpty) {
    await prefs.remove(_installedModelsKey);
  } else {
    await prefs.setString(
      _installedModelsKey,
      jsonEncode(installed.map((m) => m.toJson()).toList()),
    );
  }
  final service = LocalAiAdvisorService(
    secureStorage: const FlutterSecureStorage(),
    prefs: prefs,
  );
  GetIt.instance.registerSingleton<LocalAiAdvisorService>(service);
  return service;
}

Widget _app() {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('vi')],
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => LocalModelGuideDialog.maybeShowOnFirstUse(context),
          child: const Text('open chat'),
        ),
      ),
    ),
  );
}

class _ConfigurableProviderService extends AiProviderService {
  final changes = StreamController<void>.broadcast();
  List<AiProviderModelCatalog> catalogs = const [];

  @override
  Stream<void> get onConfigChanged => changes.stream;

  @override
  Future<bool> get hasConfiguredProvider async => catalogs.isNotEmpty;

  @override
  Future<List<AiProviderModelCatalog>> getEnabledProviderModelCatalogs() async {
    return catalogs;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LocalModelGuideDialog.resetSessionForTest();
  });

  tearDown(() => GetIt.instance.reset());

  testWidgets('the local model guide opens on the first visit only', (
    tester,
  ) async {
    await tester.runAsync(_registerLocalAi);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('open chat'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.text('Run AI on your own device'), findsOneWidget);
    expect(find.textContaining('"Install"'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('local-model-guide-open-settings')),
      findsOneWidget,
    );

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Run AI on your own device'), findsNothing);

    // A new session must not show it again: the choice is persisted.
    LocalModelGuideDialog.resetSessionForTest();
    await tester.tap(find.text('open chat'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('Run AI on your own device'), findsNothing);
  });

  testWidgets('users who already installed a local model skip the guide', (
    tester,
  ) async {
    final local = await tester.runAsync(
      () => _registerLocalAi(installed: [_installedModel]),
    );
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('open chat'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.text('Run AI on your own device'), findsNothing);
    expect(local!.chatGuideShown, isTrue);
  });

  test('an open chat picks up providers configured in Settings', () async {
    final providers = _ConfigurableProviderService();
    final bloc = AiAgentBloc(providerService: providers);
    addTearDown(bloc.close);
    expect(bloc.state.providerModelCatalogs, isEmpty);

    providers.catalogs = const [
      AiProviderModelCatalog(
        providerId: 'p',
        providerName: 'Provider',
        apiType: AiApiType.openaiCompatible,
        authMode: AiProviderAuthMode.none,
        defaultModelName: 'model-a',
        models: ['model-a'],
      ),
    ];
    providers.changes.add(null);

    final state = await bloc.stream.firstWhere(
      (s) => s.providerModelCatalogs.isNotEmpty && !s.isLoadingProviderModels,
    );
    expect(state.isProviderConfigured, isTrue);
    expect(state.selectedModelName, 'model-a');
  });

  test(
    'an open chat follows local models installed or removed in Settings',
    () async {
      final second = InstalledLocalModel(
        catalogId: 'org/small-gguf',
        displayName: 'Small',
        localPath: '/models/small.gguf',
        sizeBytes: 1,
        installedAt: DateTime(2026),
        runtimeArtifactId: 'small.gguf',
      );
      final local = await _registerLocalAi(
        installed: [_installedModel, second],
      );
      final bloc = AiAgentBloc(
        providerService: _ConfigurableProviderService(),
        localAiService: local,
      );
      addTearDown(bloc.close);
      expect(bloc.state.providerModelCatalogs, isEmpty);

      await local.uninstallModel(_installedModel.catalogId);

      final state = await bloc.stream.firstWhere(
        (s) => s.providerModelCatalogs.isNotEmpty,
      );
      final catalog = state.providerModelCatalogs.single;
      expect(catalog.providerId, AiAgentBloc.localAiProviderId);
      expect(catalog.models, ['Small']);
    },
  );
}
