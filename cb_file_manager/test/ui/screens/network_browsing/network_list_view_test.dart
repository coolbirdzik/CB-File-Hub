import 'package:cb_file_manager/ui/components/common/search_text_field.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';

import 'package:cb_file_manager/bloc/network_browsing/network_browsing_bloc.dart';
import 'package:cb_file_manager/services/network_browsing/network_service_registry.dart';
import 'package:cb_file_manager/ui/screens/folder_list/components/folder_item.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/screens/network_browsing/network_browser_screen.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/widgets/adaptive_file_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'network_recovery_test.dart' show ListingService, host;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory preferencesDirectory;
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  setUpAll(() async {
    preferencesDirectory = await Directory.systemTemp.createTemp(
      'cb-network-list-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          paths,
          (_) async => preferencesDirectory.path,
        );
    SharedPreferences.setMockInitialValues({});
    await UserPreferences.instance.init();
    await UserPreferences.instance.setNetworkBrowserViewMode(ViewMode.list);
  });
  tearDownAll(() async {
    await SqliteDatabaseProvider.closeSharedDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, null);
    await preferencesDirectory.delete(recursive: true);
  });
  testWidgets('network List uses compact file rows and column-filling layout', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'network_browser_view_mode': ViewMode.list.index,
    });
    await tester.binding.setSurfaceSize(const Size(1100, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = ListingService();
    final registry = NetworkServiceRegistry.withServices([service]);
    await registry.connect(
      serviceName: 'SMB',
      host: '192.0.2.1',
      username: 'test',
    );
    final network = NetworkBrowsingBloc(registry: registry);
    final tabs = TabManagerBloc();
    addTearDown(service.started.close);
    addTearDown(network.close);
    addTearDown(tabs.close);
    const path = '#network/SMB/192.0.2.1/share/';
    final added = tabs.stream.first;
    tabs.add(AddTab(path: path));
    await added;
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: network),
          BlocProvider.value(value: tabs),
        ],
        child: host(
          NetworkBrowserScreen(path: path, tabId: tabs.state.activeTabId!),
        ),
      ),
    );
    for (var i = 0; i < 20 && !service.pending.containsKey(path); i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(service.pending, contains(path));
    service.pending[path]!.complete(
      List.generate(
        60,
        (i) => Directory('${path}Folder ${i.toString().padLeft(2, '0')}'),
      ),
    );
    // Preferences use SQLite; allow its real IO to complete outside fake time.
    for (
      var i = 0;
      i < 100 && find.byType(AdaptiveFileList).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(AdaptiveFileList), findsOneWidget);
    final rows = tester.widgetList<FolderItem>(find.byType(FolderItem));
    expect(rows, isNotEmpty);
    expect(rows.every((row) => row.compact && !row.showItemBackground), isTrue);
    final first = tester.getTopLeft(find.text('Folder 00'));
    final second = tester.getTopLeft(find.text('Folder 01'));
    expect(first.dx, second.dx);
    expect(second.dy, greaterThan(first.dy));
    final columnStarts = find.byType(FolderItem).evaluate().where((element) {
      final box = element.renderObject! as RenderBox;
      return box.localToGlobal(Offset.zero).dx > first.dx + 200;
    });
    expect(columnStarts, isNotEmpty);
    await tester.tap(find.text('Folder 00'));
    await tester.pump();
    expect(
      tester.widgetList<FolderItem>(find.byType(FolderItem)).first.isSelected,
      isTrue,
    );
    expect(tabs.state.activeTab!.path, path);
    final screenContext = tester.element(find.byType(NetworkBrowserScreen));
    final l10n = AppLocalizations.of(screenContext)!;
    await tester.tap(find.byTooltip(l10n.search));
    await tester.pumpAndSettle();
    final search = find.descendant(
      of: find.byType(SearchTextField),
      matching: find.byType(TextField),
    );
    expect(search, findsOneWidget);
    await tester.enterText(search, 'Folder 01');
    await tester.pump();
    expect(find.text('Folder 00'), findsNothing);
    expect(find.byType(FolderItem), findsOneWidget);
    await tester.enterText(search, 'missing-file');
    await tester.pump();
    expect(find.byType(FolderItem), findsNothing);
    expect(
      find.text(l10n.noFilesFoundQuery({'query': 'missing-file'})),
      findsOneWidget,
    );
    await tester.enterText(search, '');
    await tester.pump();
    expect(find.text('Folder 00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });
}
