import 'package:cb_file_manager/ui/tab_manager/components/navigation_bar.dart';
import 'package:cb_file_manager/ui/tab_manager/components/address_bar_menu.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

void main() {
  for (final network in [false, true]) {
    testWidgets('navigation fits narrow widths (network: $network)', (
      tester,
    ) async {
      final controller = TextEditingController(text: r'C:\Users\Documents');
      addTearDown(controller.dispose);
      var back = 0;
      var up = 0;
      var refreshed = 0;
      String? submitted;
      for (final width in [88.7, 40.0, 120.0, 240.0, 600.0, 88.7]) {
        await tester.pumpWidget(
          fluent.FluentApp(
            home: Material(
              child: Center(
                child: SizedBox(
                  width: width,
                  height: 56,
                  child: PathNavigationBar(
                    tabId: 'narrow',
                    pathController: controller,
                    currentPath: network
                        ? '#network/smb/server/Sshare/folder'
                        : controller.text,
                    tabPath: controller.text,
                    isNetworkPath: network,
                    onPathSubmitted: (path) => submitted = path,
                    canNavigateBack: true,
                    onNavigateBack: () => back++,
                    canNavigateToParent: true,
                    onNavigateToParent: () => up++,
                    menuItems: [
                      AddressBarMenuItems.refresh(onTap: () => refreshed++),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'width $width');
      }

      Future<void> select(String title) async {
        await tester.tap(find.byType(AddressBarMenu));
        await tester.pumpAndSettle();
        await tester.tap(find.text(title).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await select('Go back');
      await select('Up');
      await select('Làm mới');
      expect(back, 1);
      expect(up, 1);
      expect(refreshed, 1);
      if (!network) {
        await tester.tapAt(
          tester.getTopLeft(find.byType(PathNavigationBar)) +
              const Offset(12, 28),
        );
        await tester.pumpAndSettle();
        expect(find.byType(EditableText), findsOneWidget);
        await tester.enterText(find.byType(EditableText), r'D:\Projects');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(submitted, r'D:\Projects');
      }
      expect(find.byIcon(PhosphorIconsLight.dotsThree), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
