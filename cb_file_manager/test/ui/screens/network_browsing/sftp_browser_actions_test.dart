import 'dart:io';
import 'package:cb_file_manager/ui/components/common/file_view_shell.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';

import 'package:cb_file_manager/bloc/network_browsing/network_browsing_bloc.dart';
import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/services/network_browsing/network_service_base.dart';
import 'package:cb_file_manager/services/network_browsing/network_service_registry.dart';
import 'package:cb_file_manager/services/network_browsing/sftp_service.dart';
import 'package:cb_file_manager/ui/screens/network_browsing/network_browser_screen.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/widgets/drag_selection_region.dart';
import 'package:cb_file_manager/ui/widgets/selection_geometry_item.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/ssh/memory_transfer_file_system.dart';
import 'network_recovery_test.dart' show host;

const _root = '#network/SFTP/user%40server%3A22';

class _SftpFixture extends NetworkServiceBase implements SftpFileAccess {
  @override
  final MemoryTransferFileSystem transferFileSystem = MemoryTransferFileSystem()
    ..addFile('/alpha.txt', 'alpha')
    ..addFile('/beta.txt', 'beta')
    ..mkdirs('/target');
  @override
  String get serviceName => 'SFTP';
  @override
  String get basePath => 'sftp://user@server:22';
  @override
  bool get isConnected => true;
  @override
  bool isAvailable() => true;
  @override
  String resolveRemotePath(String path) =>
      path == _root || path == '$_root/' ? '/' : path.substring(_root.length);
  @override
  Future<ConnectionResult> connect({
    required String host,
    required String username,
    String? password,
    int? port,
    Map<String, dynamic>? additionalOptions,
  }) async => ConnectionResult(success: true, connectedPath: basePath);
  @override
  Future<List<FileSystemEntity>> listDirectory(String path) async => [
    for (final entry in await transferFileSystem.list(resolveRemotePath(path)))
      if (entry.isDirectory)
        Directory('$_root${entry.path}')
      else
        File('$_root${entry.path}'),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory preferencesDirectory;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  setUpAll(() async {
    preferencesDirectory = await Directory.systemTemp.createTemp(
      'cb-sftp-actions-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => preferencesDirectory.path,
        );
    SharedPreferences.setMockInitialValues({});
    await UserPreferences.instance.init();
    await UserPreferences.instance.setNetworkBrowserViewMode(ViewMode.list);
  });
  tearDownAll(() async {
    await SqliteDatabaseProvider.closeSharedDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    expect(
      preferencesDirectory.parent.absolute.path,
      Directory.systemTemp.absolute.path,
    );
    expect(
      preferencesDirectory.path.split(Platform.pathSeparator).last,
      startsWith('cb-sftp-actions-'),
    );
    await preferencesDirectory.delete(recursive: true);
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // UserPreferences uses the suite's SQLite database, so resetting the
    // SharedPreferences mock alone does not clear the preceding zoom test.
    await UserPreferences.instance.setNetworkBrowserViewMode(ViewMode.list);
    await UserPreferences.instance.setGridZoomLevel(
      UserPreferences.defaultGridZoomLevel,
    );
  });

  Future<({MemoryTransferFileSystem fs, TabManagerBloc tabs})> pumpBrowser(
    WidgetTester tester, {
    ViewMode mode = ViewMode.list,
  }) async {
    await tester.runAsync(
      () => UserPreferences.instance.setNetworkBrowserViewMode(mode),
    );
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _SftpFixture();
    final registry = NetworkServiceRegistry.withServices([service]);
    await registry.connect(
      serviceName: 'SFTP',
      host: 'server',
      username: 'user',
    );
    final network = NetworkBrowsingBloc(registry: registry);
    final tabs = TabManagerBloc();
    addTearDown(network.close);
    addTearDown(tabs.close);
    final added = tabs.stream.first;
    tabs.add(AddTab(path: '$_root/'));
    await added;
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: network),
          BlocProvider.value(value: tabs),
        ],
        child: host(
          BlocBuilder<TabManagerBloc, TabManagerState>(
            builder: (_, state) => NetworkBrowserScreen(
              path: state.activeTab!.path,
              tabId: state.activeTabId!,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 100 && find.text('alpha.txt').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(find.text('alpha.txt'), findsOneWidget);
    return (fs: service.transferFileSystem, tabs: tabs);
  }

  Future<void> chord(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'SFTP wheel zoom updates immediately while preference writes are pending',
    (tester) async {
      await tester.runAsync(() => UserPreferences.instance.setGridZoomLevel(4));
      await pumpBrowser(tester, mode: ViewMode.grid);
      final before =
          (tester.widget<GridView>(find.byType(GridView)).gridDelegate
                  as SliverGridDelegateWithFixedCrossAxisCount)
              .crossAxisCount;
      final shell = tester.widget<FileViewShell>(find.byType(FileViewShell));
      shell.onViewScaleDelta!(1);
      shell.onViewScaleDelta!(1);
      await tester.pump();
      final after =
          (tester.widget<GridView>(find.byType(GridView)).gridDelegate
                  as SliverGridDelegateWithFixedCrossAxisCount)
              .crossAxisCount;
      expect(after, lessThan(before));
      var saved = -1;
      for (var i = 0; i < 100 && saved != 2; i++) {
        saved = (await tester.runAsync(
          () => UserPreferences.instance.getGridZoomLevel(),
        ))!;
        await tester.pump();
      }
      expect(saved, 2);
      expect(tester.takeException(), isNull);
    },
  );

  for (final cut in [false, true]) {
    testWidgets(
      'SFTP browser ${cut ? 'moves' : 'copies'} multiple files across folders',
      (tester) async {
        final fixture = await pumpBrowser(tester);
        await tester.tap(
          find.byKey(const ValueKey('file-list-item-$_root/alpha.txt')),
        );
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.tap(
          find.byKey(const ValueKey('file-list-item-$_root/beta.txt')),
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        await chord(
          tester,
          cut ? LogicalKeyboardKey.keyX : LogicalKeyboardKey.keyC,
        );
        fixture.tabs.add(
          UpdateTabPath(fixture.tabs.state.activeTabId!, '$_root/target'),
        );
        await tester.pumpAndSettle();
        await chord(tester, LogicalKeyboardKey.keyV);
        expect(fixture.fs.text('/target/alpha.txt'), 'alpha');
        expect(fixture.fs.text('/target/beta.txt'), 'beta');
        expect(fixture.fs.text('/alpha.txt'), cut ? isNull : 'alpha');
        expect(fixture.fs.text('/beta.txt'), cut ? isNull : 'beta');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('SFTP keeps failed cut items for a retry in another folder', (
    tester,
  ) async {
    final fixture = await pumpBrowser(tester);
    fixture.fs.addFile('/target/alpha.txt', 'occupied');
    fixture.fs.mkdirs('/next');
    await tester.tap(
      find.byKey(const ValueKey('file-list-item-$_root/alpha.txt')),
    );
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyX);
    fixture.tabs.add(
      UpdateTabPath(fixture.tabs.state.activeTabId!, '$_root/target'),
    );
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyV);
    expect(fixture.fs.text('/alpha.txt'), 'alpha');
    expect(fixture.fs.text('/target/alpha.txt'), 'occupied');
    await tester.tap(find.widgetWithText(CbButton, 'Close'));
    await tester.pumpAndSettle();
    fixture.tabs.add(
      UpdateTabPath(fixture.tabs.state.activeTabId!, '$_root/next'),
    );
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyV);
    expect(fixture.fs.text('/alpha.txt'), isNull);
    expect(fixture.fs.text('/next/alpha.txt'), 'alpha');
    expect(fixture.fs.text('/target/alpha.txt'), 'occupied');
    expect(tester.takeException(), isNull);
  });

  for (final mode in [
    ViewMode.list,
    ViewMode.grid,
    ViewMode.details,
    ViewMode.tree,
  ]) {
    for (final keyboard in [false, true]) {
      testWidgets(
        'SFTP ${mode.name} ${keyboard ? 'key after toolbar focus' : 'toolbar Delete'} deletes both selected files',
        (tester) async {
          final fixture = await pumpBrowser(tester, mode: mode);
          Finder item(String name) => mode == ViewMode.tree
              ? find.text(name)
              : find.byKey(ValueKey('file-${mode.name}-item-$_root/$name'));
          await tester.tap(item('alpha.txt'));
          await tester.pumpAndSettle();
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.tap(item('beta.txt'));
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pumpAndSettle();
          final selection = tester
              .element(item('alpha.txt'))
              .read<SelectionBloc>()
              .state;
          expect(selection.selectedCount, 2);
          final toolbar = find.byKey(
            const ValueKey('sftp-browser-delete-selection'),
          );
          if (keyboard) {
            Focus.of(
              tester.element(
                find.descendant(of: toolbar, matching: find.byType(Icon)).first,
              ),
            ).requestFocus();
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.delete);
          } else {
            await tester.tap(toolbar);
          }
          await tester.pumpAndSettle();
          expect(fixture.fs.files.length, 2);
          await tester.tap(
            find.byKey(const ValueKey('sftp-browser-confirm-delete')),
          );
          await tester.pumpAndSettle();
          expect(fixture.fs.files, isEmpty);
          expect(fixture.fs.dirs, contains('/target'));
          expect(tester.widget<CbButton>(toolbar).onPressed, isNull);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final mode in [
    ViewMode.list,
    ViewMode.grid,
    ViewMode.details,
    ViewMode.tree,
  ]) {
    testWidgets(
      'SFTP ${mode.name} rectangle selection and Delete remove all selected entries',
      (tester) async {
        final fixture = await pumpBrowser(tester, mode: mode);
        final region = find.byType(DragSelectionRegion);
        final rect = tester.getRect(region);
        for (final path in ['/target', '/alpha.txt', '/beta.txt']) {
          final item = find.byWidgetPredicate(
            (widget) =>
                widget is SelectionGeometryItem && widget.path == '$_root$path',
          );
          expect(item, findsOneWidget);
          final bounds = tester.getRect(item);
          expect(
            bounds.intersect(rect),
            bounds,
            reason: 'The rectangle fixture must keep $path fully visible.',
          );
        }
        final gesture = await tester.startGesture(
          rect.bottomRight - const Offset(12, 12),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveTo(rect.topLeft + const Offset(1, 1));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
        final selection = tester
            .element(find.text('alpha.txt'))
            .read<SelectionBloc>()
            .state;
        expect(selection.selectedCount, 3);
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.pumpAndSettle();
        expect(fixture.fs.files.length, 2);
        await tester.tap(
          find.byKey(const ValueKey('sftp-browser-confirm-delete')),
        );
        await tester.pumpAndSettle();
        expect(fixture.fs.files, isEmpty);
        expect(fixture.fs.dirs, {'/'});
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('SFTP file and folder context menus use remote actions', (
    tester,
  ) async {
    final fixture = await pumpBrowser(tester);
    for (final name in ['alpha.txt', 'target']) {
      await tester.tap(
        find.byKey(
          ValueKey(
            '${name == 'target' ? 'folder' : 'file'}-list-item-$_root/$name',
          ),
        ),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 100 && find.text('Cut').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(find.text('Cut'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      if (name == 'target') {
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(fixture.tabs.state.activeTab!.path, '$_root/target');
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
    }
  });

  testWidgets('SFTP rename preserves text editing and does not delete files', (
    tester,
  ) async {
    final fixture = await pumpBrowser(tester);
    await tester.tap(
      find.byKey(const ValueKey('file-list-item-$_root/alpha.txt')),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('sftp-transfer-name'));
    await tester.enterText(input, 'renamed.txt');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(fixture.fs.text('/renamed.txt'), 'alpha');
    expect(fixture.fs.text('/alpha.txt'), isNull);
    expect(fixture.fs.text('/beta.txt'), 'beta');
    expect(tester.takeException(), isNull);
  });
}
