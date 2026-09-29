import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/config/theme_config.dart';
import 'package:cb_file_manager/services/app_update/app_update_models.dart';
import 'package:cb_file_manager/services/app_update/app_update_service.dart';
import 'package:cb_file_manager/ui/components/app_update/app_update_dialog.dart';
import 'package:cb_file_manager/ui/components/common/operation_progress_overlay.dart';
import 'package:cb_file_manager/ui/controllers/operation_progress_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _update = AppUpdateInfo(
  version: '1.2.0',
  releaseNotes:
      "## What's Changed\n\n"
      '- feat: show updates in the status center (abc1234)\n'
      '- fix: keep permissions after updating (bcd2345)\n'
      '- ci: bump build number (cde3456)\n',
  assetSize: 1024 * 1024,
);

Widget _host(Widget child) => MaterialApp(
  theme: ThemeConfig.getLightTheme(),
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: const [Locale('en'), Locale('vi')],
  home: Scaffold(body: child),
);

void main() {
  final service = AppUpdateService.instance;

  tearDown(() => service.debugSetState(phase: AppUpdatePhase.idle));

  testWidgets('Status Center lists an available update with its actions', (
    tester,
  ) async {
    service.debugSetState(
      phase: AppUpdatePhase.available,
      update: _update,
      currentVersion: '1.1.0',
    );
    await tester.pumpWidget(
      _host(StatusCenterPanel(controller: OperationProgressController())),
    );
    await tester.pumpAndSettle();

    expect(find.text('App update'), findsOneWidget);
    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('1.1.0'), findsOneWidget);
    expect(find.text('1.2.0'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text("What's new"), findsOneWidget);
    expect(find.text('No internal notifications'), findsNothing);

    service.debugSetState(phase: AppUpdatePhase.upToDate);
    await tester.pump();
    expect(find.text('App update'), findsNothing);
    expect(find.text('No internal notifications'), findsOneWidget);
  });

  testWidgets('Status Center shows download progress', (tester) async {
    service.debugSetState(
      phase: AppUpdatePhase.downloading,
      update: _update,
      currentVersion: '1.1.0',
      progress: 0.5,
      receivedBytes: 512 * 1024,
      totalBytes: 1024 * 1024,
    );
    await tester.pumpWidget(
      _host(StatusCenterPanel(controller: OperationProgressController())),
    );
    await tester.pumpAndSettle();

    expect(find.text('50%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('update dialog groups the release notes', (tester) async {
    service.debugSetState(
      phase: AppUpdatePhase.available,
      update: _update,
      currentVersion: '1.1.0',
    );
    await tester.pumpWidget(_host(const AppUpdateDialog()));
    await tester.pumpAndSettle();

    expect(find.text('NEW FEATURES'), findsOneWidget);
    expect(find.text('Show updates in the status center'), findsOneWidget);
    expect(find.text('FIXES'), findsOneWidget);
    expect(find.text('Keep permissions after updating'), findsOneWidget);
    expect(find.textContaining('bump build number'), findsNothing);
    expect(find.textContaining('abc1234'), findsNothing);
  });

  test('an update stays unseen until the Status Center is opened', () {
    service.debugSetState(phase: AppUpdatePhase.available, update: _update);
    expect(service.hasUnseenUpdate, isTrue);

    service.markUpdateSeen();
    expect(service.hasUnseenUpdate, isFalse);

    service.debugSetState(phase: AppUpdatePhase.upToDate);
    expect(service.hasUnseenUpdate, isFalse);
  });
}
