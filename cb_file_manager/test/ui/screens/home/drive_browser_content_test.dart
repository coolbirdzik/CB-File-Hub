import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/services/drive/drive_info.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/tab_manager/components/drive_browser_content.dart';
import 'package:cb_file_manager/ui/tab_manager/components/drive_avatar.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final family in manifest) {
      final loader = FontLoader(family['family'] as String);
      for (final font in family['fonts'] as List) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });
  final drives = [
    DriveInfo(
      path: 'C:/',
      displayName: 'Windows',
      filesystem: 'NTFS',
      kind: DriveKind.fixed,
      isSystemVolume: true,
      space: DriveSpaceInfo.fromTotalFree(512000000000, 142300000000),
    ),
    DriveInfo(
      path: 'D:/',
      displayName: 'Projects & media',
      filesystem: 'NTFS',
      kind: DriveKind.fixed,
      space: DriveSpaceInfo.fromTotalFree(2000000000000, 843600000000),
    ),
    DriveInfo(
      path: 'E:/',
      displayName: 'Travel backup',
      filesystem: 'exFAT',
      kind: DriveKind.removable,
      space: DriveSpaceInfo.fromTotalFree(128000000000, 6500000000),
    ),
    const DriveInfo(
      path: 'Z:/',
      displayName: 'Studio archive',
      kind: DriveKind.network,
    ),
    const DriveInfo(
      path: '\\\\wsl.localhost\\Debian\\',
      displayName: 'Debian',
      kind: DriveKind.wsl,
      filesystem: 'WSL',
    ),
  ];
  final boundaryKey = GlobalKey();
  Future<void> mount(
    WidgetTester tester,
    ViewMode mode, {
    double width = 1100,
    Brightness brightness = Brightness.light,
    bool properties = false,
    Set<DriveDetailsColumn>? visibleColumns,
    ValueChanged<DriveInfo>? select,
    ValueChanged<DriveInfo>? open,
    void Function(DriveInfo, Offset)? menu,
    ValueChanged<SortOption>? sort,
    ValueChanged<DriveGroup?>? filter,
    DriveGroup? groupFilter,
  }) async {
    tester.view.physicalSize = Size(width, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final theme = CbThemeBuilder.build(
      brightness: brightness,
      accent: Colors.teal,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('vi')],
        home: Scaffold(
          body: RepaintBoundary(
            key: boundaryKey,
            child: ColoredBox(
              color: theme.cb.colors.canvas.withValues(alpha: 1),
              child: DriveBrowserContent(
                drives: groupFilter == null
                    ? drives
                    : drives.where((d) => d.group == groupFilter).toList(),
                availableDrives: drives,
                groupFilter: groupFilter,
                onGroupFilterChanged: filter ?? (_) {},
                viewMode: mode,
                gridZoom: 4,
                selectedPaths: groupFilter == null ? const {'D:/'} : const {},
                focusedPath: groupFilter == null ? 'D:/' : null,
                showProperties: properties,
                visibleColumns:
                    visibleColumns ?? DriveDetailsColumn.values.toSet(),
                onSelect: select ?? (_) {},
                onOpen: open ?? (_) {},
                onMenu: menu ?? (_, _) {},
                onSort: sort ?? (_) {},
                sortOption: SortOption.nameAsc,
                hierarchyBuilder: () => const Text('Hierarchy'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final mode in [
    ViewMode.list,
    ViewMode.tiles,
    ViewMode.grid,
    ViewMode.details,
  ]) {
    for (final width in [360.0, 800.0, 1200.0]) {
      testWidgets('${mode.name} fits width $width', (tester) async {
        await mount(tester, mode, width: width);
        expect(find.byKey(ValueKey('drive-mode-${mode.name}')), findsOneWidget);
        expect(find.byKey(const ValueKey('drive-entry-C:/')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'drive row selects, double-click opens and menu targets the drive',
    (tester) async {
      DriveInfo? selected, opened, menuDrive;
      await mount(
        tester,
        ViewMode.list,
        select: (d) => selected = d,
        open: (d) => opened = d,
        menu: (d, _) => menuDrive = d,
      );
      final entry = find.byKey(const ValueKey('drive-entry-C:/'));
      await tester.tap(entry);
      await tester.pump(const Duration(milliseconds: 400));
      expect(selected?.path, 'C:/');
      await tester.tap(entry);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(opened?.path, 'C:/');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(
        find.descendant(of: entry, matching: find.byType(IconButton)),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(menuDrive?.path, 'C:/');
    },
  );

  for (final mode in [
    ViewMode.list,
    ViewMode.tiles,
    ViewMode.grid,
    ViewMode.details,
  ]) {
    testWidgets(
      '${mode.name} selects on the first mouse frame without a second tap toggle',
      (tester) async {
        var selections = 0;
        var opens = 0;
        await mount(
          tester,
          mode,
          select: (_) => selections++,
          open: (_) => opens++,
        );
        final row = find.byKey(const ValueKey('drive-entry-C:/'));
        // The label stays clear of the row's trailing menu button.
        final position = tester.getCenter(
          find.descendant(of: row, matching: find.text('Windows')),
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.down(position);
        await tester.pump();
        expect(selections, 1);
        expect(opens, 0);
        final surface = tester.widget<AnimatedContainer>(
          find
              .descendant(of: row, matching: find.byType(AnimatedContainer))
              .first,
        );
        expect(surface.duration, Duration.zero);
        await mouse.up();
        await tester.pump(const Duration(milliseconds: 400));
        expect(selections, 1);
        expect(opens, 0);
        final second = await tester.startGesture(
          position,
          kind: PointerDeviceKind.mouse,
        );
        await second.up();
        await tester.pump(const Duration(milliseconds: 50));
        final third = await tester.startGesture(
          position,
          kind: PointerDeviceKind.mouse,
        );
        await third.up();
        await tester.pump(const Duration(milliseconds: 400));
        expect(selections, 3);
        expect(opens, 1);
        await mouse.removePointer();
      },
    );
  }

  testWidgets('details column sorts and properties adapt to narrow windows', (
    tester,
  ) async {
    SortOption? selected;
    await mount(tester, ViewMode.details, sort: (s) => selected = s);
    await tester.tap(find.text('Name ↑'));
    await tester.pump();
    expect(selected, SortOption.nameDesc);
    await mount(tester, ViewMode.grid, width: 360, properties: true);
    expect(find.byType(DriveInspector), findsOneWidget);
    expect(find.text('Projects & media'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('details can hide columns and Enter activates a focused drive', (
    tester,
  ) async {
    await mount(
      tester,
      ViewMode.details,
      visibleColumns: const {DriveDetailsColumn.name, DriveDetailsColumn.total},
    );
    expect(find.text('File system'), findsNothing);
    expect(find.text('Total'), findsOneWidget);
    DriveInfo? opened;
    await mount(tester, ViewMode.grid, open: (drive) => opened = drive);
    final rowFocus = Focus.of(tester.element(find.text('Windows')));
    rowFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opened?.path, 'C:/');
  });

  testWidgets(
    'WSL is discoverable from the group filter and uses its Linux glyph',
    (tester) async {
      DriveGroup? selected;
      await mount(tester, ViewMode.grid, filter: (group) => selected = group);
      await tester.tap(find.byKey(const ValueKey('drive-filter-wsl')));
      await tester.pumpAndSettle();
      expect(selected, DriveGroup.wsl);
      expect(find.byIcon(PhosphorIconsFill.windowsLogo), findsOneWidget);
      expect(find.byType(DriveAvatar), findsWidgets);
      // The filter remains visible even when the WSL card starts below the fold.
      expect(find.byIcon(PhosphorIconsLight.linuxLogo), findsWidgets);
    },
  );

  testWidgets('light and dark storage previews', (tester) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final preview in [
        (ViewMode.grid, null),
        (ViewMode.list, null),
        (ViewMode.details, null),
        (ViewMode.grid, DriveGroup.wsl),
      ]) {
        final mode = preview.$1;
        await mount(
          tester,
          mode,
          width: 1200,
          brightness: brightness,
          properties: mode == ViewMode.grid && preview.$2 == null,
          groupFilter: preview.$2,
        );
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final dir = await Directory(
            'build/drive-browser-preview',
          ).create(recursive: true);
          await File(
            '${dir.path}/${brightness.name}-${preview.$2 == null ? mode.name : 'wsl'}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
  });

  testWidgets(
    'WSL card opens the selected UNC root without a fake capacity bar',
    (tester) async {
      DriveInfo? opened;
      await mount(
        tester,
        ViewMode.grid,
        groupFilter: DriveGroup.wsl,
        open: (drive) => opened = drive,
      );
      expect(find.text('1 location'), findsOneWidget);
      expect(find.byType(DriveCapacityBar), findsNothing);
      await tester.tap(find.text('Open'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(opened?.path, '\\\\wsl.localhost\\Debian\\');
    },
  );
}
