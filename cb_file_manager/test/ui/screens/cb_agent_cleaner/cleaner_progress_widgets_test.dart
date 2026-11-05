import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cleaner_progress_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('preparation count updates before deletion has a known total', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final progress = ValueNotifier<(int, int, String?)?>((250, 0, r'C:\cache'));
    addTearDown(progress.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: CleanerCleanProgress(progress: progress)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Preparing files · 250 found'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );
    progress.value = (1200, 0, r'C:\cache\next');
    await tester.pump();
    expect(find.text('Preparing files · 1200 found'), findsOneWidget);
    expect(find.text(r'C:\cache\next'), findsOneWidget);
    progress.value = (300, 1200, r'C:\cache\delete.tmp');
    await tester.pump();
    expect(find.text('Preparing files · 1200 found'), findsNothing);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.25,
    );
    expect(tester.takeException(), isNull);
  });
}
