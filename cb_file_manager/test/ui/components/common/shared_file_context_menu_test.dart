import 'dart:async';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/design_system/cb_theme_builder.dart';
import 'package:cb_file_manager/ui/components/common/shared_file_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_content_overlay.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../integration_test/e2e_keys.dart' as e2e_keys;

Future<void> openPopup(
  WidgetTester tester,
  List<ContextMenuAction> actions, {
  Offset position = const Offset(80, 450),
  Locale locale = const Locale('en'),
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: CbThemeBuilder.build(
        brightness: Brightness.light,
        accent: Colors.blue,
      ),
      locale: locale,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('vi')],
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              showContextMenuPopup(
                context: context,
                globalPosition: position,
                sections: [ContextMenuSection(actions: actions)],
              ),
            ),
            child: const Text('Open test menu'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open test menu'));
  await tester.pump();
}

const loadedActions = <ContextMenuSection>[
  ContextMenuSection(
    actions: [
      ContextMenuAction(
        id: 'loaded',
        label: 'WinRAR action',
        icon: PhosphorIconsLight.file,
      ),
    ],
  ),
];

void main() {
  for (final actionId in ['new_folder', 'new_file']) {
    testWidgets('creation helper opens New directly for $actionId', (
      tester,
    ) async {
      final opened = <String>[];
      String? selected;
      await openPopup(tester, [
        for (final id in ['view', 'sort', 'new_submenu'])
          ContextMenuAction(
            id: id,
            // Keyed navigation also works without English display labels.
            label: id == 'new_submenu' ? 'Tạo mới' : id,
            icon: PhosphorIconsLight.folder,
            loadChildSections: (_) async {
              opened.add(id);
              await Future<void>.delayed(const Duration(milliseconds: 200));
              return [
                ContextMenuSection(
                  actions: [
                    ContextMenuAction(
                      id: id == 'new_submenu'
                          ? (actionId == 'new_file'
                                ? 'new_file_more'
                                : actionId)
                          : '${id}_option',
                      label: id == 'new_submenu'
                          ? 'Mục cần tạo'
                          : 'Other option',
                      icon: PhosphorIconsLight.file,
                      onSelected: (_) => selected = actionId,
                    ),
                  ],
                ),
              ];
            },
          ),
      ], locale: const Locale('vi'));
      await e2e_keys.tapContextMenuItem(tester, actionId);
      expect(opened, ['new_submenu']);
      expect(selected, actionId);
      expect(find.byType(PopupMenuItem<String>), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('menu helper retains generic submenu discovery', (tester) async {
    var selected = false;
    await openPopup(tester, [
      ContextMenuAction(
        id: 'custom_submenu',
        label: 'Custom tools',
        icon: PhosphorIconsLight.folder,
        childSections: [
          ContextMenuSection(
            actions: [
              ContextMenuAction(
                id: 'custom_action',
                label: 'Run custom tool',
                icon: PhosphorIconsLight.file,
                onSelected: (_) => selected = true,
              ),
            ],
          ),
        ],
      ),
    ]);
    await e2e_keys.tapContextMenuItem(tester, 'custom_action');
    expect(selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final fail in [false, true]) {
    testWidgets('lazy menu shows busy cursor until settled (error: $fail)', (
      tester,
    ) async {
      final pending = Completer<List<ContextMenuSection>>();
      var calls = 0;
      var loadingWasPainted = false;
      await openPopup(tester, [
        ContextMenuAction(
          id: 'apps',
          label: 'Third-party apps',
          icon: PhosphorIconsLight.appWindow,
          loadChildSections: (_) {
            calls++;
            loadingWasPainted = find
                .byType(CircularProgressIndicator)
                .evaluate()
                .isNotEmpty;
            return pending.future;
          },
        ),
      ]);
      expect(calls, 0);
      final trigger = find.byKey(const ValueKey('context-menu-action-apps'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(trigger));
      await tester.pump();
      expect(calls, 1);
      expect(loadingWasPainted, isTrue);
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.progress,
      );
      await mouse.moveTo(tester.getCenter(find.text('Loading...')));
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.progress,
      );
      await mouse.moveTo(tester.getCenter(trigger));
      if (fail) {
        pending.completeError(StateError('Shell extension failed'));
      } else {
        pending.complete(loadedActions);
      }
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        isNot(SystemMouseCursors.progress),
      );
      expect(calls, 1);
      await mouse.removePointer();
      await tester.tapAt(const Offset(750, 20));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in [const Locale('en'), const Locale('vi')]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets('quick labels fit app theme: $locale at $textScale', (
        tester,
      ) async {
        final l10n = await const AppLocalizationsDelegate().load(locale);
        await openPopup(
          tester,
          [
            for (final entry in {
              'cut': l10n.cut,
              'copy': l10n.copy,
              'share': l10n.share,
              'paste': l10n.pasteHere,
              'delete': l10n.moveToTrash,
            }.entries)
              ContextMenuAction(
                id: entry.key,
                label: entry.value,
                icon: PhosphorIconsLight.file,
              ),
          ],
          locale: locale,
          textScale: textScale,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final strip = tester.getRect(
          find.byKey(const ValueKey('context-menu-quick-actions')),
        );
        for (final id in ['cut', 'copy', 'share', 'paste', 'delete']) {
          final label = find.descendant(
            of: find.byKey(ValueKey('context-menu-action-$id')),
            matching: find.byType(Text),
          );
          expect(label, findsOneWidget);
          expect(tester.getRect(label).bottom, lessThanOrEqualTo(strip.bottom));
        }
      });
    }
  }

  for (final position in [
    const Offset(80, 80),
    const Offset(780, 580),
    const Offset(80, 310),
  ]) {
    testWidgets('quick actions stay in one row near $position', (tester) async {
      final selected = <String>[];
      await openPopup(tester, [
        for (var i = 0; i < 20; i++)
          ContextMenuAction(
            id: 'extra-$i',
            label: 'Additional action $i',
            icon: PhosphorIconsLight.file,
          ),
        for (final id in ['delete', 'paste', 'share', 'copy', 'cut'])
          ContextMenuAction(
            id: id,
            label: id,
            icon: PhosphorIconsLight.file,
            onSelected: (_) => selected.add(id),
          ),
      ], position: position);
      await tester.pumpAndSettle();

      final strip = tester.getRect(
        find.byKey(const ValueKey('context-menu-quick-actions')),
      );
      expect(strip.left, greaterThanOrEqualTo(8));
      expect(strip.right, lessThanOrEqualTo(792));
      expect(strip.top, greaterThanOrEqualTo(8));
      expect(strip.bottom, lessThanOrEqualTo(592));
      final edge = position.dy > 300 ? strip.bottom : strip.top;
      expect((edge - position.dy).abs(), lessThanOrEqualTo(10));
      var previousX = -1.0;
      for (final id in ['cut', 'copy', 'share', 'paste', 'delete']) {
        final button = find.byKey(ValueKey('context-menu-action-$id'));
        expect(button, findsOneWidget);
        final center = tester.getCenter(button);
        expect(center.dy, strip.center.dy);
        expect(center.dx, greaterThan(previousX));
        previousX = center.dx;
      }
      await tester.tap(find.byKey(const ValueKey('context-menu-action-copy')));
      await tester.pumpAndSettle();
      expect(selected, ['copy']);
      expect(
        find.byKey(const ValueKey('context-menu-quick-actions')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('disabled quick action does not dismiss or invoke', (
    tester,
  ) async {
    var selected = false;
    await openPopup(tester, [
      ContextMenuAction(
        id: 'share',
        label: 'Share',
        icon: PhosphorIconsLight.shareNetwork,
        isEnabled: false,
        onSelected: (_) => selected = true,
      ),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('context-menu-action-share')));
    await tester.pumpAndSettle();
    expect(selected, isFalse);
    expect(find.byTooltip('Share'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('context-menu-quick-actions')),
      findsOneWidget,
    );
  });

  testWidgets('submenu receives mouse clicks above the real tab overlay', (
    tester,
  ) async {
    var selected = false;
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
          body: Padding(
            padding: const EdgeInsets.fromLTRB(100, 60, 40, 30),
            child: TabContentOverlay(
              child: Builder(
                builder: (context) => Align(
                  alignment: Alignment.topLeft,
                  child: TextButton(
                    onPressed: () => unawaited(
                      showContextMenuPopup(
                        context: context,
                        globalPosition: const Offset(180, 150),
                        sections: [
                          ContextMenuSection(
                            actions: [
                              ContextMenuAction(
                                id: 'tab_apps',
                                label: 'Tab apps',
                                icon: PhosphorIconsLight.appWindow,
                                childSections: [
                                  ContextMenuSection(
                                    actions: [
                                      ContextMenuAction(
                                        id: 'tab_extract',
                                        label: 'Tab extract',
                                        icon: PhosphorIconsLight.file,
                                        onSelected: (_) => selected = true,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    child: const Text('Open tab menu'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open tab menu'));
    await tester.pump();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Tab apps')));
    await tester.pump();
    expect(find.text('Tab extract'), findsOneWidget);
    final childPosition = tester.getCenter(find.text('Tab extract'));
    await mouse.moveTo(childPosition);
    await tester.pump();
    await mouse.down(childPosition);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(selected, isTrue);
    expect(find.text('Tab apps'), findsNothing);
    expect(find.text('Open tab menu'), findsOneWidget);
    await mouse.removePointer();
  });

  testWidgets('hover crosses into a short submenu near the window bottom', (
    tester,
  ) async {
    await openPopup(tester, [
      const ContextMenuAction(
        id: 'apps',
        label: 'Third-party apps',
        icon: PhosphorIconsLight.appWindow,
        childSections: loadedActions,
      ),
    ]);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Third-party apps')));
    await tester.pump();
    final parentPosition = tester.getCenter(find.text('Third-party apps'));
    final childPosition = tester.getCenter(find.text('WinRAR action'));
    expect((childPosition.dy - parentPosition.dy).abs(), lessThan(50));
    // Crossing empty space must not dismiss the active submenu on a 120ms timer.
    await mouse.moveTo(const Offset(700, 550));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('WinRAR action'), findsOneWidget);
    await mouse.moveTo(childPosition);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('WinRAR action'), findsOneWidget);
    await mouse.removePointer();
    await tester.tapAt(const Offset(750, 20));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'loaded submenu updates in place while the pointer is inside it',
    (tester) async {
      final pending = Completer<List<ContextMenuSection>>();
      var calls = 0;
      await openPopup(tester, [
        ContextMenuAction(
          id: 'apps',
          label: 'Third-party apps',
          icon: PhosphorIconsLight.appWindow,
          loadChildSections: (_) {
            calls++;
            return pending.future;
          },
        ),
      ]);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Third-party apps')));
      await tester.pump();
      final loadingPanel = find
          .ancestor(
            of: find.text('Loading...'),
            matching: find.byType(Material),
          )
          .first;
      final panelElement = tester.element(loadingPanel);
      await mouse.moveTo(tester.getCenter(find.text('Loading...')));
      await tester.pump(const Duration(milliseconds: 300));
      pending.complete(loadedActions);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('WinRAR action'), findsOneWidget);
      final loadedPanel = find
          .ancestor(
            of: find.text('WinRAR action'),
            matching: find.byType(Material),
          )
          .first;
      expect(tester.element(loadedPanel), same(panelElement));
      await mouse.moveTo(tester.getCenter(find.text('Third-party apps')));
      await tester.pump();
      expect(calls, 1);
      expect(find.text('Loading...'), findsNothing);
      await mouse.removePointer();
      await tester.tapAt(const Offset(750, 20));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'third-party discovery starts after root paint and is ready before hover',
    (tester) async {
      final pending = Completer<List<ContextMenuSection>>();
      var calls = 0;
      await openPopup(tester, [
        ContextMenuAction(
          id: 'apps',
          label: 'Third-party apps',
          icon: PhosphorIconsLight.appWindow,
          preloadChildren: true,
          loadChildSections: (_) {
            calls++;
            return pending.future;
          },
        ),
      ]);
      expect(find.text('Third-party apps'), findsOneWidget);
      await tester.pump();
      expect(calls, 1);
      expect(find.text('Loading...'), findsNothing);
      pending.complete(loadedActions);
      await tester.pump();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Third-party apps')));
      await tester.pump();
      expect(find.text('WinRAR action'), findsOneWidget);
      expect(find.text('Loading...'), findsNothing);
      expect(calls, 1);
      await mouse.removePointer();
      await tester.tapAt(const Offset(750, 20));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('lazy submenu does not delay the root context menu', (
    tester,
  ) async {
    final childSections = Completer<List<ContextMenuSection>>();
    var loaderCalls = 0;
    var childSelected = false;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                unawaited(
                  showContextMenuPopup(
                    context: context,
                    globalPosition: const Offset(80, 80),
                    sections: <ContextMenuSection>[
                      ContextMenuSection(
                        actions: <ContextMenuAction>[
                          ContextMenuAction(
                            id: 'lazy_submenu',
                            label: 'Lazy submenu',
                            icon: PhosphorIconsLight.appWindow,
                            loadChildSections: (_) {
                              loaderCalls++;
                              return childSections.future;
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Open menu'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open menu'));
    await tester.pump();

    expect(find.text('Lazy submenu'), findsOneWidget);
    expect(loaderCalls, 0);

    await tester.tap(find.text('Lazy submenu'));
    await tester.pump();

    expect(loaderCalls, 1);
    expect(find.text('Loading...'), findsOneWidget);

    childSections.complete(<ContextMenuSection>[
      ContextMenuSection(
        actions: <ContextMenuAction>[
          ContextMenuAction(
            id: 'loaded_child',
            label: 'Loaded child',
            icon: PhosphorIconsLight.file,
            onSelected: (_) => childSelected = true,
          ),
        ],
      ),
    ]);
    await tester.pump();
    await tester.pump();

    expect(find.text('Loaded child'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey<String>('context-menu-action-tap-loaded_child'),
      ),
    );
    await tester.pump();

    expect(childSelected, isTrue);
    expect(find.text('Lazy submenu'), findsNothing);
  });

  testWidgets(
    'nested app submenu stays open while hovering near the right edge',
    (tester) async {
      var selected = false;
      await openPopup(tester, [
        ContextMenuAction(
          id: 'apps',
          label: 'Third-party apps',
          icon: PhosphorIconsLight.appWindow,
          childSections: [
            ContextMenuSection(
              actions: [
                ContextMenuAction(
                  id: 'winrar',
                  label: 'WinRAR',
                  icon: PhosphorIconsLight.fileArchive,
                  childSections: [
                    ContextMenuSection(
                      actions: [
                        ContextMenuAction(
                          id: 'extract',
                          label: 'Extract here',
                          icon: PhosphorIconsLight.file,
                          onSelected: (_) => selected = true,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ], position: const Offset(550, 450));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Third-party apps')));
      await tester.pump();
      await mouse.moveTo(tester.getCenter(find.text('WinRAR')));
      await tester.pump();
      final extractPosition = tester.getCenter(find.text('Extract here'));
      expect(extractPosition.dx, inInclusiveRange(8, 792));
      expect(extractPosition.dy, inInclusiveRange(8, 592));
      await mouse.moveTo(extractPosition);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('WinRAR'), findsOneWidget);
      expect(find.text('Extract here'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('context-menu-action-tap-extract')),
      );
      await tester.pumpAndSettle();
      expect(selected, isTrue);
      expect(find.text('Third-party apps'), findsNothing);
      await mouse.removePointer();
    },
  );

  testWidgets('nested lazy submenu loads only when opened', (tester) async {
    final nestedSections = Completer<List<ContextMenuSection>>();
    var nestedLoaderCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                unawaited(
                  showContextMenuPopup(
                    context: context,
                    globalPosition: const Offset(80, 80),
                    sections: <ContextMenuSection>[
                      ContextMenuSection(
                        actions: <ContextMenuAction>[
                          ContextMenuAction(
                            id: 'root_submenu',
                            label: 'Root submenu',
                            icon: PhosphorIconsLight.appWindow,
                            childSections: <ContextMenuSection>[
                              ContextMenuSection(
                                actions: <ContextMenuAction>[
                                  ContextMenuAction(
                                    id: 'nested_lazy_submenu',
                                    label: 'Nested lazy submenu',
                                    icon: PhosphorIconsLight.folder,
                                    loadChildSections: (_) {
                                      nestedLoaderCalls++;
                                      return nestedSections.future;
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Open nested menu'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open nested menu'));
    await tester.pump();
    await tester.tap(find.text('Root submenu'));
    await tester.pump();

    expect(find.text('Nested lazy submenu'), findsOneWidget);
    expect(nestedLoaderCalls, 0);

    await tester.tap(find.text('Nested lazy submenu'));
    await tester.pump();

    expect(nestedLoaderCalls, 1);
    expect(find.text('Loading...'), findsOneWidget);

    nestedSections.complete(const <ContextMenuSection>[
      ContextMenuSection(
        actions: <ContextMenuAction>[
          ContextMenuAction(
            id: 'nested_loaded_child',
            label: 'Nested loaded child',
            icon: PhosphorIconsLight.file,
          ),
        ],
      ),
    ]);
    await tester.pump();
    await tester.pump();

    expect(find.text('Nested loaded child'), findsOneWidget);
  });
}
