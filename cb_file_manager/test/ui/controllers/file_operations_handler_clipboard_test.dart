import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/helpers/core/filesystem_utils.dart';
import 'package:cb_file_manager/ui/controllers/file_operations_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Screens like the video library have no FolderListBloc above them; cutting
/// there must still fill the app-wide clipboard so another tab can paste.
Future<BuildContext> pumpWithoutFolderListBloc(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  tearDown(() => FileOperations().clearClipboard());

  testWidgets('cut without a FolderListBloc fills the shared clipboard', (
    tester,
  ) async {
    final context = await pumpWithoutFolderListBloc(tester);
    final files = [File('a.mp4'), File('b.mp4')];

    FileOperationsHandler.cutFilesToClipboard(
      context: context,
      entities: files,
    );
    await tester.pump(const Duration(seconds: 5));

    expect(FileOperations().isCutOperation, isTrue);
    expect(FileOperations().clipboardItems.map((e) => e.path), [
      'a.mp4',
      'b.mp4',
    ]);
  });

  testWidgets('copy without a FolderListBloc fills the shared clipboard', (
    tester,
  ) async {
    final context = await pumpWithoutFolderListBloc(tester);

    FileOperationsHandler.copyToClipboard(
      context: context,
      entity: File('a.mp4'),
    );
    await tester.pump(const Duration(seconds: 5));

    expect(FileOperations().isCutOperation, isFalse);
    expect(FileOperations().clipboardItems.single.path, 'a.mp4');
  });
}
