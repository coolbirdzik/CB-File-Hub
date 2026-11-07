import 'dart:io';

import 'package:cb_file_manager/models/local_ai/local_ai_advisor_model.dart';
import 'package:cb_file_manager/services/local_ai/local_ai_advisor_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  late LocalAiAdvisorService service;
  late SharedPreferences prefs;
  final payload = [1, 2, 3, 4];
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    sandbox = await Directory.systemTemp.createTemp('shared-model-registry-');
    service = LocalAiAdvisorService(
      prefs: prefs,
      documentsDirectoryProvider: () async => sandbox,
      httpClient: MockClient((_) async => http.Response.bytes(payload, 200)),
    );
  });
  tearDown(() async {
    await service.dispose();
    await sandbox.delete(recursive: true);
  });
  HuggingFaceModelEntry entry(
    LocalModelPurpose purpose, {
    String? checksum,
    int size = 4,
  }) => HuggingFaceModelEntry(
    id: 'test/${purpose.name}',
    displayName: purpose.name,
    artifactFileName: purpose == LocalModelPurpose.speech
        ? 'weights.bin'
        : 'weights.gguf',
    sizeBytes: size,
    purpose: purpose,
    sha256: checksum ?? sha256.convert(payload).toString(),
  );
  Future<InstalledLocalModel> install(HuggingFaceModelEntry e) =>
      service.installModel(e, onProgress: (_) {});
  test(
    'all tasks share storage but subtitle models cannot become the agent model',
    () async {
      final speech = await install(entry(LocalModelPurpose.speech));
      await install(entry(LocalModelPurpose.translation));
      expect(service.getManagedModels(), hasLength(2));
      expect(service.getInstalledModels(), isEmpty);
      expect(service.getSelectedModel(), isNull);
      expect(speech.isRunnableArtifact, isFalse);
      await expectLater(
        service.setSelectedModel(speech.catalogId),
        throwsStateError,
      );
      final chat = await install(entry(LocalModelPurpose.chat));
      expect(service.getSelectedModel()?.catalogId, chat.catalogId);
      expect(service.getInstalledModels(), hasLength(1));
      await service.uninstallModel(chat.catalogId);
      expect(prefs.getString('local_ai_selected_model_id'), isNull);
      expect(service.getManagedModels(), hasLength(2));
    },
  );
  test(
    'checksum and length failures never install corrupt artifacts',
    () async {
      await expectLater(
        install(entry(LocalModelPurpose.speech, checksum: '0' * 64)),
        throwsFormatException,
      );
      await expectLater(
        install(entry(LocalModelPurpose.translation, size: 5)),
        throwsFormatException,
      );
      expect(service.getManagedModels(), isEmpty);
      expect(
        sandbox
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.part')),
        isEmpty,
      );
    },
  );
  test(
    'moving the common folder preserves purpose and releases active users',
    () async {
      final speech = await install(entry(LocalModelPurpose.speech));
      var released = false;
      service.registerModelUse(speech.catalogId, () async {
        released = true;
      });
      await service.setModelStorageDirectory('${sandbox.path}/new');
      await service.moveInstalledModelsToStorage(onProgress: (_) {});
      final moved = service.getManagedModels().single;
      expect(released, isTrue);
      expect(moved.purpose, LocalModelPurpose.speech);
      expect(await File(moved.localPath).exists(), isTrue);
      expect(await File(speech.localPath).exists(), isFalse);
    },
  );
  test('legacy installed metadata still defaults to chat', () {
    final model = InstalledLocalModel.fromJson({
      'catalogId': 'old/chat',
      'displayName': 'old',
      'localPath': 'old.gguf',
      'sizeBytes': 1,
      'installedAt': 0,
    });
    expect(model.purpose, LocalModelPurpose.chat);
    expect(model.isRunnableArtifact, isTrue);
  });
  test('concurrent task downloads preserve every installed model', () async {
    await Future.wait([
      install(entry(LocalModelPurpose.speech)),
      install(entry(LocalModelPurpose.translation)),
      install(entry(LocalModelPurpose.chat)),
    ]);
    expect(
      service.getManagedModels().map((m) => m.purpose).toSet(),
      LocalModelPurpose.values.toSet(),
    );
    expect(service.getInstalledModels(), hasLength(1));
  });
}
