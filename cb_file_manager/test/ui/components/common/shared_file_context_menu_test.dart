import 'dart:async';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/ui/components/common/shared_file_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

void main() {
  testWidgets('lazy submenu does not delay the root context menu',
      (tester) async {
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
        supportedLocales: const <Locale>[
          Locale('en'),
          Locale('vi'),
        ],
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
        supportedLocales: const <Locale>[
          Locale('en'),
          Locale('vi'),
        ],
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
