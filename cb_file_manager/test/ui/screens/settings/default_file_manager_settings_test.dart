import 'dart:async';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/services/desktop_integration/default_file_manager_service.dart';
import 'package:cb_file_manager/ui/screens/settings/default_file_manager_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class _Service extends DefaultFileManagerService {
  FolderDefaultStatus current = const FolderDefaultStatus();
  Completer<void>? gate;
  bool fail = false;
  @override
  Future<FolderDefaultStatus> status() async => current;
  @override
  Future<void> enable() async {
    if (gate != null) await gate!.future;
    if (fail) throw StateError('policy denied');
    current = const FolderDefaultStatus(enabled: true, canRestore: true);
  }

  @override
  Future<void> restore() async => current = const FolderDefaultStatus();
}

void main() {
  late _Service service;
  setUp(() => service = _Service());
  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: CbThemeBuilder.build(
          brightness: Brightness.light,
          accent: Colors.teal,
        ),
        supportedLocales: const [Locale('en')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: DefaultFileManagerSettings(service: service)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('uses effective OS state and offers restore after enabling', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Set as default for folders'));
    await tester.pumpAndSettle();
    expect(
      find.text('CB File Hub is the default folder opener.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Restore previous default'));
    await tester.pumpAndSettle();
    expect(
      find.text('CB File Hub is not the default folder opener.'),
      findsOneWidget,
    );
  });

  testWidgets('blocks duplicate changes while the OS operation is pending', (
    tester,
  ) async {
    await mount(tester);
    service.gate = Completer<void>();
    await tester.tap(find.text('Set as default for folders'));
    await tester.pump();
    final button = tester.widget<CbButton>(
      find.byWidgetPredicate(
        (widget) =>
            widget is CbButton && widget.label == 'Set as default for folders',
      ),
    );
    expect(button.onPressed, isNull);
    service.gate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'shows refusal and refreshes a later choice made outside the app',
    (tester) async {
      await mount(tester);
      service.fail = true;
      await tester.tap(find.text('Set as default for folders'));
      await tester.pumpAndSettle();
      expect(find.textContaining('policy denied'), findsOneWidget);
      expect(
        find.text('CB File Hub is the default folder opener.'),
        findsNothing,
      );
      service.current = const FolderDefaultStatus(
        enabled: true,
        canRestore: true,
      );
      await tester.tap(find.text('Refresh status'));
      await tester.pumpAndSettle();
      expect(
        find.text('CB File Hub is the default folder opener.'),
        findsOneWidget,
      );
    },
  );
}
