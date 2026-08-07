import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cleaner_utilities_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _destinations = <CleanerUtilityDestination>[
  CleanerUtilityDestination(
    id: 'diskCleaner',
    title: 'Disk usage',
    description: 'Inspect folders and clean junk',
    group: 'Storage',
    icon: Icons.storage_rounded,
  ),
  CleanerUtilityDestination(
    id: 'appInsights',
    title: 'Apps',
    description: 'Review installed apps and their data',
    group: 'Storage',
    icon: Icons.apps_rounded,
  ),
];

Widget _buildShell({
  required String selectedId,
  required ValueChanged<String> onSelected,
}) {
  return MaterialApp(
    home: Scaffold(
      body: CleanerUtilitiesShell(
        title: 'CB Agent Cleaner',
        subtitle: 'Utilities for this PC',
        selectedId: selectedId,
        destinations: _destinations,
        onSelected: onSelected,
        child: const ColoredBox(
          key: ValueKey<String>('utility-content'),
          color: Colors.transparent,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('desktop shell exposes a scalable utility sidebar',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? selected;
    await tester.pumpWidget(
      _buildShell(
        selectedId: 'diskCleaner',
        onSelected: (id) => selected = id,
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('cleaner-subfeature-selector')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('cleaner-utility-diskCleaner')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('cleaner-utility-appInsights')),
      findsOneWidget,
    );
    expect(find.text('STORAGE'), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('utility-content')), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('cleaner-utility-appInsights')),
    );
    expect(selected, 'appInsights');
  });

  testWidgets('compact shell switches utilities through a popup',
      (tester) async {
    tester.view.physicalSize = const Size(760, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? selected;
    await tester.pumpWidget(
      _buildShell(
        selectedId: 'diskCleaner',
        onSelected: (id) => selected = id,
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('cleaner-utility-popup')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('cleaner-utility-appInsights')),
      findsNothing,
    );

    await tester
        .tap(find.byKey(const ValueKey<String>('cleaner-utility-popup')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apps').last);
    await tester.pumpAndSettle();

    expect(selected, 'appInsights');
  });
}
