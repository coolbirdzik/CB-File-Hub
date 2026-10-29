import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/models/local_ai/local_ai_advisor_model.dart';
import 'package:cb_file_manager/services/local_ai/local_ai_advisor_service.dart';
import 'package:cb_file_manager/services/local_ai/local_model_downloads.dart';
import 'package:cb_file_manager/ui/screens/settings/local_ai_advisor_settings_section.dart';
import 'package:cb_file_manager/ui/screens/settings/settings_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _entry = HuggingFaceModelEntry(
  id: 'org/tiny-gguf',
  displayName: 'Tiny',
  sizeBytes: 4,
  artifactFileName: 'tiny.gguf',
);

/// A download server whose body the test feeds chunk by chunk.
class _Server {
  StreamController<List<int>> body = StreamController<List<int>>();
  int status = 200;

  late final client = MockClient.streaming((request, _) async {
    return http.StreamedResponse(
      status == 200 ? body.stream : const Stream.empty(),
      status,
      contentLength: status == 200 ? 4 : 0,
    );
  });
}

/// Exercise a recommendation below the lazy list's initial viewport even on
/// Windows, where the platform's normal recommendation happens to be first.
class _TestLocalAiService extends LocalAiAdvisorService {
  String? recommendedModelId;
  _TestLocalAiService({
    required super.prefs,
    required super.httpClient,
    required super.documentsDirectoryProvider,
  });

  @override
  HuggingFaceModelEntry get pinnedModel => recommendedModelId != null
      ? catalogEntryFor(recommendedModelId!)!
      : super.pinnedModel;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  late _Server server;
  late _TestLocalAiService service;
  late LocalModelDownloads downloads;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues({});
    sandbox = await Directory.systemTemp.createTemp('cb-model-downloads-');
    server = _Server();
    service = _TestLocalAiService(
      prefs: await SharedPreferences.getInstance(),
      httpClient: server.client,
      documentsDirectoryProvider: () async => sandbox,
    );
    downloads = LocalModelDownloads(service);
  });

  tearDown(() async {
    await GetIt.instance.reset();
    await sandbox.delete(recursive: true);
  });

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 500 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue);
  }

  File? partFile() => sandbox
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.part'))
      .firstOrNull;

  test('a download runs on its own and installs the model', () async {
    final completed = downloads.onCompleted.first;
    downloads.start(_entry);
    expect(downloads.isDownloading(_entry.id), isTrue);

    server.body
      ..add([1, 2])
      ..add([3, 4]);
    await server.body.close();

    expect((await completed).id, _entry.id);
    expect(downloads.downloads, isEmpty);
    expect(service.getInstalledModels().single.catalogId, _entry.id);
  });

  test('cancelling deletes the partial file and installs nothing', () async {
    downloads.start(_entry);
    server.body.add([1, 2]);
    await until(() => downloads[_entry.id]!.downloadedBytes == 2);

    downloads.cancel(_entry.id);
    server.body.add([3]);
    await until(() => downloads.downloads.isEmpty);

    expect(downloads.downloads, isEmpty);
    expect(partFile(), isNull);
    expect(service.getInstalledModels(), isEmpty);
    await server.body.close();
  });

  test('a failed download stays listed until retried or dismissed', () async {
    server.status = 404;
    downloads.start(_entry);
    await until(() => downloads[_entry.id]!.failed);

    final failed = downloads[_entry.id]!;
    expect(failed.failed, isTrue);
    expect(failed.error, contains('404'));

    server.status = 200;
    downloads.start(_entry);
    expect(downloads.isDownloading(_entry.id), isTrue);
    downloads.cancel(_entry.id);
    server.body.add([1]);
    await until(() => downloads.downloads.isEmpty);
    await server.body.close();
  });

  for (final recommendedModelId in [
    null,
    'litert-community/gemma-4-E2B-it-litert-lm',
    'litert-community/Qwen3.5-0.8B',
  ]) {
    testWidgets('the setup guide lands on an installer that downloads in the '
        'background (recommendation=${recommendedModelId ?? 'platform default'})', (
      tester,
    ) async {
      service.recommendedModelId = recommendedModelId;
      GetIt.instance
        ..registerSingleton<LocalAiAdvisorService>(service)
        ..registerSingleton<LocalModelDownloads>(downloads);
      pendingLocalModelInstaller.value = true;
      addTearDown(() => pendingLocalModelInstaller.value = false);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('en'), Locale('vi')],
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: SingleChildScrollView(
              child: LocalAiAdvisorSettingsSection(
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
                    }) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
      final catalog = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(ListView),
      );
      // Wait for catalog loading, not for a badge that may be below the fold on
      // Linux/macOS. The installer uses a lazy ListView.
      for (var i = 0; i < 200 && catalog.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }

      // The installer opened by itself and the flag was consumed.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(pendingLocalModelInstaller.value, isFalse);
      final pinned = service.pinnedModel;
      final install = find.byKey(ValueKey('local-ai-install-${pinned.id}'));
      await tester.scrollUntilVisible(
        install,
        200,
        scrollable: find.descendant(
          of: catalog,
          matching: find.byType(Scrollable),
        ),
      );
      // ensureVisible changes the scroll offset synchronously, but layout is
      // updated on the next frame. Without this pump the middle catalog entry
      // can still report a position underneath the dialog's Close button.
      await tester.pump();
      expect(find.text('Recommended'), findsOneWidget);
      expect(install.hitTestable(), findsOneWidget);
      await tester.tap(install.hitTestable());
      await tester.pump();
      expect(downloads.isDownloading(pinned.id), isTrue);

      // Closing the installer leaves the download running under Installed models.
      await tester.tap(find.text('Close'));
      // The progress bar animates until bytes arrive, so pump instead of settle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Downloading ${pinned.displayName}'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // Cancelling is covered above; here it only stops the pending request.
      downloads.cancel(pinned.id);
      // Nothing reads the body in this zone, so closing must not be awaited.
      unawaited(server.body.close());
    });
  }
}
