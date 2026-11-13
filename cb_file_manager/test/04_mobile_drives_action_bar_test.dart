import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/tab_manager/mobile/mobile_file_actions_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

void main() {
  testWidgets('04.01 drives actions include search, sort and navigation', (
    tester,
  ) async {
    MobileFileActionsController.clearAll();
    final controller = MobileFileActionsController.forTab('tab_drives');
    controller.actionBarProfile = MobileActionBarProfile.drivesMinimal;
    controller.currentViewMode = ViewMode.grid;
    controller.currentSortOption = SortOption.nameAsc;
    final queries = <String?>[];
    SortOption? selectedSort;
    controller.onSearchSubmitted = queries.add;
    controller.onSortOptionSelected = (option) => selectedSort = option;

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

    expect(find.byType(IconButton), findsNWidgets(6));
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byTooltip('Forward'), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsOneWidget);
    expect(find.byIcon(PhosphorIconsLight.magnifyingGlass), findsOneWidget);
    expect(find.byIcon(PhosphorIconsLight.sortAscending), findsOneWidget);
    expect(find.byIcon(PhosphorIconsLight.dotsThreeVertical), findsNothing);

    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.tap(find.byTooltip('Forward'));
    await tester.pump();

    expect(backPressed, equals(1));
    expect(forwardPressed, equals(1));

    await tester.tap(find.byTooltip('Sort'));
    await tester.pumpAndSettle();
    expect(find.text('Date modified (newest first)'), findsNothing);
    expect(find.byType(ListTile), findsNWidgets(8));
    await tester.tap(find.byType(ListTile).at(3));
    await tester.pumpAndSettle();
    expect(selectedSort, SortOption.sizeDesc);

    await tester.tap(find.byIcon(PhosphorIconsLight.squaresFour));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNWidgets(6));
    expect(find.byIcon(PhosphorIconsLight.gridNine), findsOneWidget);
    expect(find.byIcon(PhosphorIconsLight.columns), findsOneWidget);
    Navigator.of(tester.element(find.byType(ListTile).first)).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(PhosphorIconsLight.magnifyingGlass));
    await tester.pumpAndSettle();
    expect(find.text('Search storage by name or path'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'D:');
    await tester.pump();
    expect(queries.last, 'D:');
    await tester.tap(find.byIcon(PhosphorIconsLight.x));
    await tester.pump();
    expect(queries.last, isNull);
    await tester.tap(find.byIcon(PhosphorIconsLight.arrowLeft).last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    MobileFileActionsController.clearAll();
  });
}
