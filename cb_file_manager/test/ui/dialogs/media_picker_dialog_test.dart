import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/config/languages/english_localizations.dart';
import 'package:cb_file_manager/config/languages/vietnamese_localizations.dart';
import 'package:cb_file_manager/ui/dialogs/media_picker_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

final _documentsPath = p.join(
  Platform.isWindows ? r'C:\picker-home' : '/picker-home',
  'Documents',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalPathProvider = PathProviderPlatform.instance;
  late _PickerPathProvider paths;

  setUp(() {
    paths = _PickerPathProvider();
    PathProviderPlatform.instance = paths;
  });

  tearDown(() {
    paths.delayDocuments = false;
    for (final request in paths.pendingDocuments) {
      if (!request.isCompleted) request.complete(_documentsPath);
    }
    PathProviderPlatform.instance = originalPathProvider;
  });

  testWidgets('desktop sidebar initializes after localization is available', (
    tester,
  ) async {
    await IOOverrides.runZoned(() async {
      final locale = ValueNotifier(const Locale('en'));
      addTearDown(locale.dispose);
      await _openPicker(tester, locale);

      final l10n = EnglishLocalizations();
      expect(tester.takeException(), isNull);
      expect(find.text(l10n.home), findsOneWidget);
      expect(find.text(l10n.quickAccess.toUpperCase()), findsOneWidget);
      expect(find.text(l10n.thisPC.toUpperCase()), findsOneWidget);

      await tester.tap(find.text(l10n.cancel.toUpperCase()));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    }, createDirectory: _PickerDirectory.new);
  });

  testWidgets('an older sidebar load cannot overwrite the current locale', (
    tester,
  ) async {
    await IOOverrides.runZoned(() async {
      paths.delayDocuments = true;
      final locale = ValueNotifier(const Locale('en'));
      addTearDown(locale.dispose);
      await _openPicker(tester, locale);
      expect(paths.pendingDocuments, hasLength(1));

      locale.value = const Locale('vi');
      await tester.pumpAndSettle();
      expect(paths.pendingDocuments, hasLength(2));

      paths.delayDocuments = false;
      paths.pendingDocuments.last.complete(_documentsPath);
      await tester.pumpAndSettle();
      final l10n = VietnameseLocalizations();
      expect(find.text(l10n.home), findsOneWidget);

      paths.pendingDocuments.first.complete(_documentsPath);
      await tester.pumpAndSettle();
      expect(find.text(l10n.home), findsOneWidget);
      expect(find.text(EnglishLocalizations().home), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text(l10n.cancel.toUpperCase()));
      await tester.pumpAndSettle();
    }, createDirectory: _PickerDirectory.new);
  });

  testWidgets('closing the picker while its sidebar loads is safe', (
    tester,
  ) async {
    await IOOverrides.runZoned(() async {
      paths.delayDocuments = true;
      final locale = ValueNotifier(const Locale('en'));
      addTearDown(locale.dispose);
      await _openPicker(tester, locale);
      expect(paths.pendingDocuments, hasLength(1));

      await tester.tap(find.text(EnglishLocalizations().cancel.toUpperCase()));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      paths.delayDocuments = false;
      paths.pendingDocuments.single.complete(_documentsPath);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }, createDirectory: _PickerDirectory.new);
  });
}

Future<void> _openPicker(
  WidgetTester tester,
  ValueNotifier<Locale> locale,
) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ValueListenableBuilder<Locale>(
      valueListenable: locale,
      builder: (context, locale, child) => MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('vi')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showMediaPickerDialog(
                context,
                MediaPickerConfig(
                  initialPath: p.join(p.dirname(_documentsPath), 'media'),
                ),
              ),
              child: const Text('Open picker'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open picker'));
  await tester.pumpAndSettle();
}

class _PickerPathProvider extends PathProviderPlatform {
  bool delayDocuments = false;
  final pendingDocuments = <Completer<String?>>[];

  @override
  Future<String?> getApplicationDocumentsPath() {
    if (!delayDocuments) return Future.value(_documentsPath);
    final request = Completer<String?>();
    pendingDocuments.add(request);
    return request.future;
  }
}

class _PickerDirectory implements Directory {
  _PickerDirectory(this.path);

  @override
  final String path;

  @override
  Directory get parent => _PickerDirectory(p.dirname(path));

  @override
  bool existsSync() => true;

  @override
  Future<bool> exists() async => true;

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => const Stream.empty();

  @override
  Future<String> resolveSymbolicLinks() async => path;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
