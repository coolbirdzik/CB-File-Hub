import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cleaner_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _mb = 1024 * 1024;
const _gb = 1024 * _mb;

void main() {
  DiskTreeNode file(String dir, String name, int size) => DiskTreeNode(
    name: name,
    fullPath: '$dir\\$name',
    isFile: true,
    sizeBytes: size,
    fileCount: 1,
  );

  DiskTreeNode dir(String path, List<DiskTreeNode> children) => DiskTreeNode(
    name: path.split(r'\').last,
    fullPath: path,
    sizeBytes: children.fold(0, (sum, c) => sum + c.sizeBytes),
    fileCount: children.length,
    children: children,
  );

  final movie = file(r'C:\Videos', 'movie.mkv', 3 * _gb);
  final iso = file(r'C:\Images', 'win.iso', 5 * _gb);
  final small = file(r'C:\Images', 'note.txt', 200 * _mb);
  final root = DiskTreeNode(
    name: r'C:\',
    fullPath: r'C:\',
    sizeBytes: movie.sizeBytes + iso.sizeBytes + small.sizeBytes,
    children: [
      dir(r'C:\Videos', [movie]),
      dir(r'C:\Images', [iso, small]),
    ],
  );
  final now = DateTime.now();
  final old = [
    FullDiskScanInsight(
      name: 'win.iso',
      path: iso.fullPath,
      isFile: true,
      sizeBytes: iso.sizeBytes,
      lastModified: now.subtract(const Duration(days: 800)),
      lastAccessed: now.subtract(const Duration(days: 800)),
    ),
    FullDiskScanInsight(
      name: 'note.txt',
      path: small.fullPath,
      isFile: true,
      sizeBytes: small.sizeBytes,
      lastModified: now.subtract(const Duration(days: 200)),
      lastAccessed: now.subtract(const Duration(days: 200)),
    ),
  ];

  Future<List<String>> pump(WidgetTester tester) async {
    final revealed = <String>[];
    tester.view.physicalSize = const Size(1300, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SingleChildScrollView(
            child: CleanerDashboard(
              root: root,
              oldLargeItems: old,
              formatBytes: (bytes) => '${(bytes / _gb).toStringAsFixed(1)} GB',
              formatDate: (date) => '${date.year}',
              onReveal: revealed.add,
              onOpen: (_, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return revealed;
  }

  Finder row(DiskTreeNode node) =>
      find.byKey(ValueKey('cleaner-dashboard-row-${node.fullPath}'));

  testWidgets('starts collapsed and opens one card at a time', (tester) async {
    final revealed = await pump(tester);
    expect(find.text('Heavy folders'), findsOneWidget);
    expect(find.text('Old & unused'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('cleaner-dashboard-detail-largeFiles')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('cleaner-dashboard-card-largeFiles')),
    );
    await tester.pumpAndSettle();
    expect(row(iso), findsOneWidget);
    expect(row(movie), findsOneWidget);
    expect(row(small), findsNothing, reason: 'Under the 1 GB default');

    await tester.tap(
      find.byKey(ValueKey('cleaner-dashboard-large-min-${10 * _gb}')),
    );
    await tester.pumpAndSettle();
    expect(row(iso), findsNothing);
    expect(find.text('Nothing matches these conditions.'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('cleaner-dashboard-card-oldUnused')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('cleaner-dashboard-detail-largeFiles')),
      findsNothing,
    );
    expect(row(iso), findsOneWidget);
    expect(row(small), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('cleaner-dashboard-old-age-730')),
    );
    await tester.pumpAndSettle();
    expect(row(iso), findsOneWidget);
    expect(row(small), findsNothing, reason: 'Used within two years');

    await tester.tap(row(iso));
    expect(revealed, [iso.fullPath]);

    await tester.tap(
      find.byKey(const ValueKey('cleaner-dashboard-card-oldUnused')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('cleaner-dashboard-detail-oldUnused')),
      findsNothing,
    );
  });

  testWidgets('file types list the largest files of a group', (tester) async {
    await pump(tester);
    await tester.tap(
      find.byKey(const ValueKey('cleaner-dashboard-card-fileTypes')),
    );
    await tester.pumpAndSettle();
    // Largest group first: disk images.
    expect(row(iso), findsOneWidget);
    expect(row(movie), findsNothing);
    await tester.tap(find.textContaining('Videos'));
    await tester.pumpAndSettle();
    expect(row(movie), findsOneWidget);
  });
}
