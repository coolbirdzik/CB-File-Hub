import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/tab_manager/mobile/mobile_file_actions_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

void main() {
  testWidgets('04.01 drives action profile shows minimal mobile actions', (
    tester,
  ) async {
    MobileFileActionsController.clearAll();
    final controller = MobileFileActionsController.forTab('tab_drives');
    controller.actionBarProfile = MobileActionBarProfile.drivesMinimal;
    controller.currentViewMode = ViewMode.grid;

    int backPressed = 0;
    int forwardPressed = 0;
    controller.onBack = () => backPressed++;
    controller.onForward = () => forwardPressed++;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('vi')],
        home: Scaffold(
          body: Builder(
            builder: (context) => controller.buildMobileActionBar(context),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(IconButton), findsNWidgets(4));
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byTooltip('Forward'), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsOneWidget);
    expect(find.byIcon(PhosphorIconsLight.magnifyingGlass), findsNothing);
    expect(find.byIcon(PhosphorIconsLight.sortAscending), findsNothing);
    expect(find.byIcon(PhosphorIconsLight.dotsThreeVertical), findsNothing);

    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.tap(find.byTooltip('Forward'));
    await tester.pump();

    expect(backPressed, equals(1));
    expect(forwardPressed, equals(1));
  });
}
