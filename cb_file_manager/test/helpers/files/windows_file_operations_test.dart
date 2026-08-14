import 'package:cb_file_manager/helpers/files/windows_file_operations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cb_file_manager/file_operations');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('elevated delete sends only the supplied paths and elevation flag',
      () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return true;
    });

    const paths = <String>[r'E:\protected\one', r'E:\protected\two'];
    final result = await WindowsFileOperations.deleteItems(
      sources: paths,
      permanent: true,
      silent: true,
      requireElevation: true,
    );

    expect(result, isTrue);
    expect(captured?.method, 'deleteItems');
    expect(captured?.arguments, <String, Object>{
      'sources': paths,
      'permanent': true,
      'silent': true,
      'requireElevation': true,
    });
  });
}
