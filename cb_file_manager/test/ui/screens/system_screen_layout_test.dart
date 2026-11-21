import 'package:cb_file_manager/ui/screens/system_screen.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_content_overlay.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final showAppBar in [true, false]) {
    testWidgets('network system page reserves toolbar space: $showAppBar', (
      tester,
    ) async {
      const tabBarKey = ValueKey('tab-bar');
      const contentKey = ValueKey('network-home-content');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: const PreferredSize(
              preferredSize: Size.fromHeight(48),
              child: SizedBox(key: tabBarKey, height: 48),
            ),
            body: TabContentOverlay(
              child: SystemScreen(
                title: 'SMB Network',
                systemId: '#smb',
                icon: Icons.computer,
                showAppBar: showAppBar,
                child: Column(
                  key: contentKey,
                  children: [
                    const Text('Network discovery is disabled'),
                    Expanded(
                      child: ListView(
                        children: const [Text('Saved connections')],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final content = tester.getRect(find.byKey(contentKey));
      final tabBar = tester.getRect(find.byKey(tabBarKey));
      if (showAppBar) {
        final toolbar = tester.getRect(find.byType(AppBar));
        expect(toolbar.top, greaterThanOrEqualTo(tabBar.bottom));
        expect(
          content.top,
          greaterThanOrEqualTo(toolbar.bottom),
          reason:
              'The SMB warning and connection list must begin below its AppBar.',
        );
      } else {
        expect(
          content.top,
          tabBar.bottom,
          reason: 'Pages without a toolbar must not get an empty top gap.',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
}
