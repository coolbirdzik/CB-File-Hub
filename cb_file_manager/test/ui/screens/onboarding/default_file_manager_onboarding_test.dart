import 'dart:async';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/services/desktop_integration/default_file_manager_service.dart';
import 'package:cb_file_manager/ui/screens/onboarding/default_file_manager_onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Setup extends DefaultFileManagerService {
  FolderDefaultStatus current = const FolderDefaultStatus();
  bool platformSupported = true;
  bool fail = false;
  int enableCalls = 0;
  Completer<void>? gate;
  Completer<FolderDefaultStatus>? readGate;
  int statusCalls = 0;
  @override
  bool get supported => platformSupported;
  @override
  Future<FolderDefaultStatus> status() async {
    statusCalls++;
    if (statusCalls > 1 && readGate != null) return readGate!.future;
    return current;
  }

  @override
  Future<void> enable() async {
    enableCalls++;
    if (gate != null) await gate!.future;
    if (fail) throw StateError('declined');
    current = const FolderDefaultStatus(enabled: true, canRestore: true);
  }
}

void main() {
  late _Setup service;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = _Setup();
  });

  Future<void> mount(WidgetTester tester, {bool settle = true}) async {
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
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => DefaultFileManagerOnboardingScreen.showIfNeeded(
                context,
                service: service,
              ),
              child: const Text('Start onboarding'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start onboarding'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  Future<bool?> completed() async => (await SharedPreferences.getInstance())
      .getBool(DefaultFileManagerOnboardingScreen.completedKey);

  testWidgets('never registers automatically; postponing is remembered once', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('Make CB File Hub your folder opener'), findsOneWidget);
    expect(service.enableCalls, 0);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(await completed(), isTrue);
    await tester.tap(find.text('Start onboarding'));
    await tester.pumpAndSettle();
    expect(find.byType(DefaultFileManagerOnboardingScreen), findsNothing);
    expect(service.enableCalls, 0);
  });

  testWidgets('explicit setup uses the shared service and then continues', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Set as default for folders'));
    await tester.pumpAndSettle();
    expect(service.enableCalls, 1);
    expect(
      find.text('CB File Hub is the default folder opener.'),
      findsOneWidget,
    );
    expect(await completed(), isNull);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(await completed(), isTrue);
    expect(find.byType(DefaultFileManagerOnboardingScreen), findsNothing);
  });

  testWidgets('refusal stays visible and does not complete onboarding', (
    tester,
  ) async {
    service.fail = true;
    await mount(tester);
    await tester.tap(find.text('Set as default for folders'));
    await tester.pumpAndSettle();
    expect(find.textContaining('declined'), findsOneWidget);
    expect(await completed(), isNull);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets(
    'cannot postpone or navigate back while the OS is changing defaults',
    (tester) async {
      await mount(tester);
      service.gate = Completer<void>();
      await tester.tap(find.text('Set as default for folders'));
      await tester.pump();
      final skip = tester.widget<CbButton>(
        find.byWidgetPredicate(
          (widget) => widget is CbButton && widget.label == 'Not now',
        ),
      );
      expect(skip.onPressed, isNull);
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
      service.gate!.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('already default is acknowledged without another prompt', (
    tester,
  ) async {
    service.current = const FolderDefaultStatus(enabled: true);
    await mount(tester);
    expect(find.byType(DefaultFileManagerOnboardingScreen), findsNothing);
    expect(await completed(), isTrue);
    expect(service.enableCalls, 0);
  });

  testWidgets(
    'can postpone during a slow status read without disposing errors',
    (tester) async {
      service.readGate = Completer<FolderDefaultStatus>();
      await mount(tester, settle: false);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(await completed(), isTrue);
      service.readGate!.complete(const FolderDefaultStatus());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(service.enableCalls, 0);
    },
  );

  testWidgets('unavailable or unsupported platforms do not show the step', (
    tester,
  ) async {
    service.current = const FolderDefaultStatus(available: false);
    await mount(tester);
    expect(find.byType(DefaultFileManagerOnboardingScreen), findsNothing);
    expect(await completed(), isNull);
    service.platformSupported = false;
    await tester.tap(find.text('Start onboarding'));
    await tester.pumpAndSettle();
    expect(find.byType(DefaultFileManagerOnboardingScreen), findsNothing);
    expect(service.enableCalls, 0);
  });
}
