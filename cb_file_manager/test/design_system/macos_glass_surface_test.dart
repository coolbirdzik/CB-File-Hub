import 'package:cb_file_manager/design_system/fluent_chrome_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('macOS chrome keeps pointer, keyboard and overlays in Flutter', (
    tester,
  ) async {
    final nativeCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (call) async {
        nativeCalls.add(call);
        return null;
      },
    );
    final scroll = ScrollController();
    final text = TextEditingController();
    addTearDown(scroll.dispose);
    addTearDown(text.dispose);
    var pressed = 0;
    Future<void> mount(Brightness brightness, {bool highContrast = false}) =>
        tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: MediaQuery(
              data: MediaQueryData(highContrast: highContrast),
              child: Scaffold(
                body: Center(
                  child: FluentChromeSurface(
                    tint: const Color(0xFFE8E8ED),
                    tintAlpha: 0.7,
                    blurSigma: 24,
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      width: 320,
                      height: 300,
                      child: Column(
                        children: [
                          TextButton(
                            onPressed: () => pressed++,
                            child: const Text('Glass action'),
                          ),
                          TextField(controller: text),
                          PopupMenuButton<String>(
                            onSelected: (_) => pressed++,
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'open', child: Text('Open')),
                            ],
                          ),
                          Expanded(
                            child: ListView.builder(
                              controller: scroll,
                              itemCount: 30,
                              itemBuilder: (_, index) => SizedBox(
                                height: 40,
                                child: Text('Item $index'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
    for (final brightness in Brightness.values) {
      await mount(brightness);
      await tester.pumpAndSettle();
      // A mocked platform view cannot establish native event routing. Keep
      // decorative platform views out of the interaction hierarchy entirely.
      expect(find.byType(AppKitView), findsNothing);
      expect(nativeCalls, isEmpty);
      expect(find.byType(BackdropFilter), findsOneWidget);
      await tester.tap(find.text('Glass action'));
      await tester.enterText(find.byType(TextField), 'Find files');
      expect(text.text, 'Find files');
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final previousOffset = scroll.offset;
      await tester.drag(find.byType(ListView), const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(previousOffset));
    }
    expect(pressed, 4);
    await mount(Brightness.light, highContrast: true);
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(AppKitView), findsNothing);
    await tester.tap(find.text('Glass action'));
    expect(pressed, 5);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
