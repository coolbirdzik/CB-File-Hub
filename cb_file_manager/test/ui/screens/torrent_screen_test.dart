import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:cb_file_manager/ui/screens/torrent/torrent_download_dialog.dart';
import 'package:cb_file_manager/ui/screens/torrent/torrent_link_dialog.dart';
import 'package:cb_file_manager/ui/screens/torrent/torrent_client_import_dialog.dart';
import 'package:cb_file_manager/ui/tab_manager/components/navigation_bar.dart';

import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/ui/controllers/operation_progress_controller.dart';
import 'package:cb_file_manager/ui/controllers/file_operations_handler.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/components/common/browser_like_file_surface.dart';
import 'package:cb_file_manager/ui/components/common/file_details_columns.dart';
import 'package:cb_file_manager/ui/components/common/shared_file_context_menu.dart';
import 'package:cb_file_manager/ui/components/common/optimized_interaction_handler.dart';
import 'package:cb_file_manager/ui/screens/folder_list/components/file_item.dart';
import 'package:cb_file_manager/ui/screens/folder_list/components/file_grid_item.dart';
import 'package:cb_file_manager/ui/screens/folder_list/components/file_details_item.dart';
import 'package:cb_file_manager/ui/widgets/file_tree_view.dart';
import 'package:cb_file_manager/ui/widgets/miller_columns_view.dart';
import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/ui/widgets/file_preview_pane.dart';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/services/torrent/torrent_entry.dart';
import 'package:cb_file_manager/services/torrent/magnet_link.dart';
import 'package:cb_file_manager/services/torrent/torrent_launch_request.dart';
import 'package:cb_file_manager/services/torrent/torrent_import_confirmation.dart';
import 'package:cb_file_manager/services/torrent/torrent_repository.dart';
import 'package:cb_file_manager/services/torrent/torrent_service.dart';
import 'package:cb_file_manager/ui/components/common/search_text_field.dart';
import 'package:cb_file_manager/ui/screens/torrent/torrent_screen.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/sqlite_api.dart';

class _Db extends Fake implements Database {}

final class _PickedFile extends PlatformFile {
  _PickedFile(this.path);
  @override
  final String path;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _DirectoryPicker extends FilePickerPlatform {
  List<PlatformFile> files = [];
  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => files;
  String? selection;
  String? initial;
  bool parentLocked = false;
  int calls = 0;
  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    calls++;
    initial = initialDirectory;
    parentLocked = windowsOptions.lockParentWindow;
    return selection;
  }
}

Future<void> _browseDownloadFolder(
  WidgetTester tester,
  _DirectoryPicker picker,
) async {
  await tester.tap(find.byKey(const ValueKey('torrent-download-browse')));
  // Directory.exists uses real I/O; its continuations need fake test frames
  // between ancestor checks before the platform picker is reached.
  for (var attempt = 0; attempt < 100 && picker.calls == 0; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

class _Preferences extends Fake implements UserPreferences {
  @override
  Future<ViewMode> getViewMode() async => ViewMode.list;
  @override
  Future<ColumnVisibility> getColumnVisibility() async =>
      const ColumnVisibility();
  @override
  Future<bool> getShowFileTags() async => false;
  @override
  Future<SortOption> getSortOption() async => SortOption.nameAsc;
  @override
  Future<int> getGridZoomLevel() async => 4;
}

class _Repository extends TorrentRepository {
  _Repository() : super(_Db());
  final queries = <String>[];
  final held = <String, Completer<TorrentPage>>{};
  SortOption? lastSort;
  bool? lastRegex;
  int? lastOffset;
  int? lastLimit;
  String taskStatus = 'library';
  int completedBytes = 0;
  int count = 180;
  int? seeders;
  int? connections;
  TorrentEntry? importedEntry;
  @override
  Future<int?> offsetInNewestOrder(String hash) async =>
      count - 1 - int.parse(hash);
  @override
  Future<TorrentPage> page({
    int offset = 0,
    int limit = 80,
    String query = '',
    String? status,
    String? category,
    SortOption sort = SortOption.nameAsc,
    bool useRegex = false,
    bool Function()? isCancelled,
  }) async {
    queries.add(query);
    lastSort = sort;
    lastRegex = useRegex;
    lastOffset = offset;
    lastLimit = limit;
    if (held.containsKey(query)) return held[query]!.future;
    final all =
        List.generate(
              count,
              (i) => TorrentEntry.fromMap({
                'hash': '$i'.padLeft(40, '0'),
                'name': 'Torrent $i.mp4',
                'torrent_path': '/$i.torrent',
                'category': 'video',
                'group_name': '',
                'total_bytes': 100,
                'file_count': 1,
                'status': taskStatus,
                'added_at': i,
                'modified_at': i,
                'completed_bytes': completedBytes,
                'download_speed': 0,
                'seeders': seeders,
                'connections': connections,
                'upload_speed': 25,
                'uploaded_bytes': 40,
                'download_dir': taskStatus == 'library' ? null : '/downloads',
              }),
            )
            .where((entry) => entry.name.contains(query) || entry.hash == query)
            .toList();
    if (importedEntry case final entry?) {
      if (entry.name.contains(query) || entry.hash == query) all.add(entry);
    }
    if (sort == SortOption.dateDesc) {
      all.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    }
    return TorrentPage(all.skip(offset).take(limit).toList(), all.length);
  }
}

class _Service extends TorrentService {
  String configuredMode = 'index';
  String? configuredDirectory;
  List<TorrentMoveSource> cleanupSources = [];
  TorrentMovePlan? shownMove;
  TorrentMovePlan? appliedMove;
  @override
  String get storageMode => configuredMode;
  @override
  String? get libraryDirectory => configuredDirectory;
  @override
  Future<TorrentMovePlan> previewMove({String? destination}) async {
    return shownMove = TorrentMovePlan(
      destination: destination ?? configuredDirectory!,
      previousMode: configuredMode,
      previousDirectory: configuredDirectory,
      sources: cleanupSources,
    );
  }

  @override
  Future<void> setStorageMode(
    String value, {
    TorrentMovePlan? approvedMove,
  }) async {
    configuredMode = value;
    if (approvedMove != null) {
      appliedMove = approvedMove;
      configuredDirectory = approvedMove.destination;
    }
    notifyListeners();
  }

  @override
  Future<void> setLibraryDirectory(
    String value, {
    TorrentMovePlan? approvedMove,
  }) async {
    configuredDirectory = value;
    appliedMove = approvedMove;
    notifyListeners();
  }

  @override
  Future<void> organizeLibrary({TorrentMovePlan? approvedMove}) async {
    appliedMove = approvedMove;
    notifyListeners();
  }

  final opened = <String>[];
  final links = <String>[];
  final scannedRoots = <String>[];
  @override
  Future<void> scanDirectories(List<String> roots) async {
    scannedRoots.addAll(roots);
  }

  @override
  Future<TorrentEntry> openLink(
    String source, {
    TorrentMergeConfirmation? onDuplicate,
  }) async {
    links.add(source);
    if (source == 'bad-link') {
      throw const FormatException('Invalid torrent link');
    }
    return openSource(source, onDuplicate: onDuplicate);
  }

  int importRefreshes = 0;
  int syncs = 0;
  Completer<void>? refreshGate;
  String openStatus = 'active';
  final downloads = <(String, String, bool)>[];
  final paused = <String>[];
  final resumed = <String>[];
  bool duplicate = false;
  bool createNewOnOpen = false;
  int mergeApprovals = 0;
  void emitChange() => notifyListeners();
  _Service(TorrentRepository repo, SharedPreferences prefs)
    : super.forTesting(
        repository: repo,
        preferences: prefs,
        stateDirectory: '/unused',
      );
  @override
  Future<void> refreshImports() async {
    importRefreshes++;
    await refreshGate?.future;
    (repository as _Repository).count++;
  }

  @override
  Future<void> sync() async {
    syncs++;
  }

  @override
  Future<TorrentEntry> openSource(
    String source, {
    TorrentMergeConfirmation? onDuplicate,
  }) async {
    opened.add(source);
    if (createNewOnOpen) {
      final entry = TorrentEntry.fromMap({
        'hash': 'a' * 40,
        'name': 'New torrent.iso',
        'torrent_path': source,
        'category': 'other',
        'group_name': '',
        'total_bytes': 100,
        'file_count': 1,
        'status': 'library',
        'added_at': 100000,
        'modified_at': 100000,
        'completed_bytes': 0,
        'download_speed': 0,
      });
      (repository as _Repository).importedEntry = entry;
      notifyListeners();
      return entry;
    }
    final entry = TorrentEntry.fromMap({
      'hash': '0' * 40,
      'name': 'Torrent 0.mp4',
      'torrent_path': '/0.torrent',
      'category': 'video',
      'group_name': '',
      'total_bytes': 100,
      'file_count': 1,
      'status': openStatus,
      'download_dir': openStatus == 'library'
          ? null
          : p.join(Directory.systemTemp.path, 'existing-downloads'),
      'completed_bytes': 20,
      'download_speed': 0,
    });
    if (duplicate && onDuplicate != null) {
      if (!await onDuplicate(entry)) throw const TorrentImportCancelled();
      mergeApprovals++;
    }
    return entry;
  }

  @override
  Future<void> download(
    TorrentEntry entry,
    String destination, {
    bool startImmediately = true,
  }) async {
    downloads.add((entry.hash, destination, startImmediately));
    (repository as _Repository).taskStatus = startImmediately
        ? 'waiting'
        : 'paused';
  }

  @override
  Future<void> pause(TorrentEntry entry) async {
    paused.add(entry.hash);
    (repository as _Repository).taskStatus = 'paused';
  }

  @override
  Future<void> resume(TorrentEntry entry) async {
    resumed.add(entry.hash);
    (repository as _Repository).taskStatus = 'waiting';
  }
}

void main() {
  late _Repository repo;
  late TorrentService service;
  late TabManagerBloc tabs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'torrent.autoImport': false});
    locator.registerSingleton(OperationProgressController());
    repo = _Repository();
    service = _Service(repo, await SharedPreferences.getInstance());
    tabs = TabManagerBloc()..add(AddTab(path: '#torrents'));
  });
  tearDown(() async {
    service.dispose();
    await tabs.close();
    await locator.reset();
  });

  Future<void> mount(
    WidgetTester tester, {
    double width = 1100,
    String locale = 'en',
    String? initialSource,
    bool tabbed = false,
    bool settle = true,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pump();
    final torrentScreen = TorrentScreen(
      tabId: tabs.state.activeTabId!,
      service: service,
      userPreferences: _Preferences(),
      initialSource: initialSource,
    );
    await tester.pumpWidget(
      BlocProvider.value(
        value: tabs,
        child: fluent.FluentApp(
          theme: fluent.FluentThemeData(brightness: Brightness.light),
          locale: Locale(locale),
          supportedLocales: const [Locale('en'), Locale('vi')],
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => Theme(
            data: CbThemeBuilder.build(
              brightness: Brightness.light,
              accent: Colors.teal,
            ),
            child: child!,
          ),
          home: tabbed
              ? BlocBuilder<TabManagerBloc, TabManagerState>(
                  builder: (context, state) => IndexedStack(
                    index: TorrentLaunchRequest.isPath(state.activeTab!.path)
                        ? 0
                        : 1,
                    children: [torrentScreen, const Text('Other tab')],
                  ),
                )
              : torrentScreen,
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  for (final source in [
    '/silent.torrent',
    'magnet:?xt=urn:btih:${'1' * 40}',
    'https://example.test/silent.torrent',
  ]) {
    for (final start in [true, false]) {
      testWidgets(
        'hidden download options use saved folder/start $start for $source',
        (tester) async {
          final prefs = await SharedPreferences.getInstance();
          final directory = p.join(
            Directory.systemTemp.path,
            'silent-downloads',
          );
          await prefs.setBool('torrent.showDownloadDialog', false);
          await prefs.setBool('torrent.startImmediately', start);
          await prefs.setString('torrent.lastDownloadDirectory', directory);
          final fake = service as _Service;
          fake.openStatus = 'library';
          if (source.startsWith('https:')) {
            await mount(tester);
            await tester.tap(
              find.byKey(const ValueKey('torrent-add-link-action')),
            );
            await tester.pumpAndSettle();
            await tester.enterText(
              find.byKey(const ValueKey('torrent-link-input')),
              source,
            );
            await tester.tap(
              find.byKey(const ValueKey('torrent-link-confirm')),
            );
            await tester.pumpAndSettle();
          } else {
            await mount(tester, initialSource: source);
          }
          expect(find.byType(TorrentDownloadDialog), findsNothing);
          expect(fake.downloads, [('0' * 40, directory, start)]);
          expect(fake.paused, isEmpty);
          expect(fake.resumed, isEmpty);
          expect(
            find.byKey(const ValueKey('torrent-import-notice')),
            findsOneWidget,
          );
          expect(fake.importRefreshes, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final merge in [false, true]) {
    testWidgets(
      'hidden download options still require duplicate confirmation $merge',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('torrent.showDownloadDialog', false);
        await prefs.setString(
          'torrent.lastDownloadDirectory',
          Directory.systemTemp.path,
        );
        final fake = service as _Service;
        fake.openStatus = 'library';
        fake.duplicate = true;
        await mount(tester, initialSource: '/duplicate.torrent');
        expect(
          find.byKey(const ValueKey('torrent-duplicate-dialog')),
          findsOneWidget,
        );
        expect(fake.downloads, isEmpty);
        await tester.tap(
          find.byKey(
            ValueKey(merge ? 'torrent-merge-confirm' : 'torrent-merge-cancel'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(TorrentDownloadDialog), findsNothing);
        expect(fake.downloads.length, merge ? 1 : 0);
        expect(fake.mergeApprovals, merge ? 1 : 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'hidden download options reject a legacy relative default folder',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('torrent.showDownloadDialog', false);
      await prefs.setString('torrent.lastDownloadDirectory', 'relative/folder');
      (service as _Service).openStatus = 'library';
      await mount(tester, initialSource: '/new.torrent');
      expect(find.byType(TorrentDownloadDialog), findsOneWidget);
      expect((service as _Service).downloads, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opening a library row follows the hidden download options preference',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('torrent.showDownloadDialog', false);
      await prefs.setBool('torrent.startImmediately', false);
      await prefs.setString(
        'torrent.lastDownloadDirectory',
        Directory.systemTemp.path,
      );
      await mount(tester);
      final extension = tester.widget<FileContextMenuExtension>(
        find.byType(FileContextMenuExtension),
      );
      extension.onOpen!(File('/179.torrent'));
      await tester.pumpAndSettle();
      expect(find.byType(TorrentDownloadDialog), findsNothing);
      expect((service as _Service).downloads, [
        ('179'.padLeft(40, '0'), Directory.systemTemp.path, false),
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  for (final status in ['active', 'waiting', 'paused', 'complete']) {
    testWidgets('hidden download options preserve an existing $status task', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('torrent.showDownloadDialog', false);
      await prefs.setBool('torrent.startImmediately', status == 'paused');
      final fake = service as _Service;
      fake.openStatus = status;
      await mount(tester, initialSource: '/existing.torrent');
      expect(find.byType(TorrentDownloadDialog), findsNothing);
      expect(fake.downloads, isEmpty);
      expect(fake.paused, isEmpty);
      expect(fake.resumed, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'hidden download options ask for a missing folder once and then reuse it',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('torrent.showDownloadDialog', false);
      await prefs.setBool('torrent.startImmediately', false);
      final fake = service as _Service;
      fake.openStatus = 'library';
      await mount(tester, initialSource: '/first.torrent');
      expect(find.byType(TorrentDownloadDialog), findsOneWidget);
      expect(fake.downloads, isEmpty);
      final directory = p.join(Directory.systemTemp.path, 'chosen-once');
      await tester.enterText(
        find.byKey(const ValueKey('torrent-download-destination')),
        directory,
      );
      await tester.tap(find.byKey(const ValueKey('torrent-download-confirm')));
      await tester.pumpAndSettle();
      expect(fake.downloads, [('0' * 40, directory, false)]);
      expect(prefs.getBool('torrent.showDownloadDialog'), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mount(tester, initialSource: '/second.torrent');
      expect(find.byType(TorrentDownloadDialog), findsNothing);
      expect(fake.downloads, [
        ('0' * 40, directory, false),
        ('0' * 40, directory, false),
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'explicit Download to action still opens options when automatic opens hide them',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('torrent.showDownloadDialog', false);
      await prefs.setString(
        'torrent.lastDownloadDirectory',
        Directory.systemTemp.path,
      );
      await mount(tester);
      final extension = tester.widget<FileContextMenuExtension>(
        find.byType(FileContextMenuExtension),
      );
      final context = tester.element(find.byType(FileItem).first);
      final action = extension
          .sections(context, ['/179.torrent'])
          .expand((section) => section.actions)
          .singleWhere((action) => action.id == 'torrent_download');
      action.onSelected!(context);
      await tester.pumpAndSettle();
      expect(find.byType(TorrentDownloadDialog), findsOneWidget);
      expect((service as _Service).downloads, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opening options settings persist switches and chosen folder on a narrow screen',
    (tester) async {
      await mount(tester, width: 390, locale: 'vi');
      Future<void> openSettings() async {
        final button = find.byWidgetPredicate(
          (w) => w is CbButton && w.tooltip == 'Cài đặt',
        );
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      await openSettings();
      final show = find.byKey(const ValueKey('torrent-show-download-dialog'));
      await tester.ensureVisible(show);
      await tester.tap(show);
      await tester.pumpAndSettle();
      expect(service.showDownloadDialog, isFalse);
      final start = find.byKey(
        const ValueKey('torrent-default-start-immediately'),
      );
      await tester.ensureVisible(start);
      await tester.tap(start);
      await tester.pumpAndSettle();
      expect(service.startDownloadsImmediately, isFalse);
      final field = find.byKey(
        const ValueKey('torrent-default-download-directory'),
      );
      await tester.ensureVisible(field);
      final directory = p.join(Directory.systemTemp.path, 'settings-downloads');
      await tester.enterText(field, directory);
      final save = find.byKey(const ValueKey('torrent-default-download-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(service.defaultDownloadDirectory, directory);
      final previous = FilePickerPlatform.instance;
      final picker = _DirectoryPicker()..selection = Directory.systemTemp.path;
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = previous);
      final browse = find.byKey(
        const ValueKey('torrent-default-download-browse'),
      );
      await tester.ensureVisible(browse);
      await tester.tap(browse);
      for (var attempt = 0; attempt < 100 && picker.calls == 0; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(picker.calls, 1);
      expect(picker.parentLocked, isTrue);
      expect(service.defaultDownloadDirectory, Directory.systemTemp.path);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mount(tester, width: 390, locale: 'vi');
      await openSettings();
      expect(tester.widget<CheckboxListTile>(show).value, isFalse);
      expect(tester.widget<CheckboxListTile>(start).value, isFalse);
      expect(
        tester.widget<CbTextField>(field).controller!.text,
        Directory.systemTemp.path,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final entryPoint in ['browser', 'picker']) {
    testWidgets(
      'opening a torrent from $entryPoint shows the save dialog and new row without F5',
      (tester) async {
        // Dispatch and consume launch events inside the widget test's async zone.
        await tester.runAsync(() => tabs.close());
        tabs = TabManagerBloc()..add(AddTab(path: '#torrents'));
        final fake = service as _Service;
        fake.createNewOnOpen = true;
        await (await SharedPreferences.getInstance()).setBool(
          'torrent.startImmediately',
          false,
        );
        await mount(tester);
        final torrentTabId = tabs.state.activeTabId;
        await tester.tap(
          find.byWidgetPredicate(
            (w) => w is CbButton && w.tooltip == 'Next Page',
          ),
        );
        await tester.pumpAndSettle();
        expect(repo.lastOffset, 80);
        const source = '/new-file.TORRENT';
        if (entryPoint == 'browser') {
          final folder = FolderListBloc();
          addTearDown(folder.close);
          FileOperationsHandler.onFileTap(
            context: tester.element(find.byType(TorrentScreen)),
            file: File(source),
            folderListBloc: folder,
          );
        } else {
          final previous = FilePickerPlatform.instance;
          FilePickerPlatform.instance = _DirectoryPicker()
            ..files = [_PickedFile(source)];
          addTearDown(() => FilePickerPlatform.instance = previous);
          await tester.tap(find.byKey(const ValueKey('torrent-import-action')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('torrent-import-files-action')),
          );
        }
        await tester.pumpAndSettle();
        expect(fake.opened, [source]);
        expect(tabs.state.tabs, hasLength(1));
        expect(tabs.state.activeTabId, torrentTabId);
        expect(find.byType(TorrentDownloadDialog), findsOneWidget);
        expect(
          tester
              .widget<TorrentDownloadDialog>(find.byType(TorrentDownloadDialog))
              .startImmediately,
          isFalse,
        );
        expect(
          find.byKey(const ValueKey('torrent-download-browse')),
          findsOneWidget,
        );
        expect(fake.downloads, isEmpty);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('New torrent.iso'), findsOneWidget);
        expect(find.text('1–80 of 181 torrents'), findsOneWidget);
        expect(repo.lastOffset, 0);
        expect(repo.queries, everyElement(''));
        expect(fake.importRefreshes, 0);
        expect(fake.downloads, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Import menu groups client imports and supports a custom profile folder',
    (tester) async {
      await mount(tester);
      expect(
        find.byKey(const ValueKey('torrent-qbittorrent-import-action')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('torrent-import-action')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('torrent-import-files-action')),
        findsOneWidget,
      );
      for (final client in ['transmission', 'deluge']) {
        expect(
          find.byKey(ValueKey('torrent-import-$client-action')),
          findsOneWidget,
        );
      }
      // These backup/profile integrations are Windows-only in the actual UI.
      // Linux CI must verify their absence rather than skip the import test.
      for (final client in ['utorrent', 'bittorrent']) {
        expect(
          find.byKey(ValueKey('torrent-import-$client-action')),
          Platform.isWindows ? findsOneWidget : findsNothing,
        );
      }
      expect(
        find.byKey(const ValueKey('torrent-qbittorrent-import-action')),
        Platform.isWindows ? findsOneWidget : findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('torrent-import-transmission-action')),
      );
      await tester.pump();
      for (var attempt = 0; attempt < 100; attempt++) {
        final confirm = find.byKey(
          const ValueKey('torrent-client-import-confirm'),
        );
        if (confirm.evaluate().isNotEmpty &&
            tester.widget<CbButton>(confirm).onPressed != null) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.byType(TorrentClientImportDialog), findsOneWidget);
      expect(find.text('Import from Transmission'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('torrent-qbittorrent-import-action')),
        findsNothing,
      );
      final root = await tester.runAsync(
        () => Directory.systemTemp.createTemp('cb-client-profile-'),
      );
      addTearDown(() => root!.delete(recursive: true));
      await tester.enterText(
        find.byKey(const ValueKey('torrent-client-source')),
        root!.path,
      );
      await tester.tap(
        find.byKey(const ValueKey('torrent-client-import-confirm')),
      );
      for (
        var attempt = 0;
        attempt < 100 && (service as _Service).scannedRoots.isEmpty;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pumpAndSettle();
      }
      expect((service as _Service).scannedRoots, [root.path]);
      expect(service.scanRoots, contains(root.path));
      expect(find.byType(TorrentClientImportDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'client import handles missing profiles and folder picking on narrow screens',
    (tester) async {
      await mount(tester, width: 390, locale: 'vi');
      unawaited(
        showDialog<String>(
          context: tester.element(find.byType(TorrentScreen)),
          builder: (_) => TorrentClientImportDialog(
            client: 'Deluge',
            storageMode: 'copy',
            discover: () async => [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('torrent-client-import-confirm')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Chọn thư mục có sẵn chứa các file .torrent.'),
        findsOneWidget,
      );
      final previous = FilePickerPlatform.instance;
      final picker = _DirectoryPicker()..selection = Directory.systemTemp.path;
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = previous);
      await tester.tap(find.byKey(const ValueKey('torrent-client-browse')));
      await tester.pumpAndSettle();
      expect(picker.calls, 1);
      expect(picker.parentLocked, isTrue);
      expect(
        tester
            .widget<CbTextField>(
              find.byKey(const ValueKey('torrent-client-source')),
            )
            .controller!
            .text,
        Directory.systemTemp.path,
      );
      expect(
        find.text('Chọn thư mục có sẵn chứa các file .torrent.'),
        findsNothing,
      );
      await tester.tap(find.text('Hủy bỏ'));
      await tester.pumpAndSettle();
      expect((service as _Service).scannedRoots, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'client discovery preserves edits and lets users switch detected profiles',
    (tester) async {
      await mount(tester);
      final discovered = Completer<List<String>>();
      unawaited(
        showDialog<String>(
          context: tester.element(find.byType(TorrentScreen)),
          builder: (_) => TorrentClientImportDialog(
            client: 'Transmission',
            storageMode: 'index',
            discover: () => discovered.future,
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('torrent-client-source')),
        '/custom-profile',
      );
      discovered.complete(['/profile-one', '/profile-two']);
      await tester.pumpAndSettle();
      final source = tester
          .widget<CbTextField>(
            find.byKey(const ValueKey('torrent-client-source')),
          )
          .controller!;
      expect(source.text, '/custom-profile');
      final profiles = tester.widget<CbSelect<String>>(
        find.byKey(const ValueKey('torrent-client-profiles')),
      );
      profiles.onChanged!('/profile-two');
      await tester.pumpAndSettle();
      expect(source.text, '/profile-two');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect((service as _Service).scannedRoots, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final text in [
    '  magnet:?xt=urn:btih:${'1' * 40}&dn=Clipboard%20torrent  ',
    'https://example.test/file.torrent',
    'magnet:?xt=urn:btih:invalid',
    'ordinary clipboard text',
  ]) {
    testWidgets('Add link prefills only a supported clipboard magnet: $text', (
      tester,
    ) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') return {'text': text};
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('torrent-add-link-action')));
      await tester.pumpAndSettle();
      final field = tester.widget<CbTextField>(
        find.byKey(const ValueKey('torrent-link-input')),
      );
      expect(
        field.controller!.text,
        text.contains('Clipboard%20torrent') ? text.trim() : '',
      );
      expect((service as _Service).links, isEmpty);
      expect((service as _Service).downloads, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'late clipboard response keeps user edits and is safe after closing',
    (tester) async {
      var reply = Completer<Object?>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') return reply.future;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('torrent-add-link-action')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('torrent-link-input')),
        'user input',
      );
      reply.complete({'text': 'magnet:?xt=urn:btih:${'2' * 40}'});
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CbTextField>(
              find.byKey(const ValueKey('torrent-link-input')),
            )
            .controller!
            .text,
        'user input',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      reply = Completer<Object?>();
      await tester.tap(find.byKey(const ValueKey('torrent-add-link-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      reply.complete({'text': 'magnet:?xt=urn:btih:${'3' * 40}'});
      await tester.pumpAndSettle();
      expect((service as _Service).links, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unavailable clipboard leaves Add link editable', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          throw PlatformException(code: 'clipboard-unavailable');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('torrent-add-link-action')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CbTextField>(find.byKey(const ValueKey('torrent-link-input')))
          .controller!
          .text,
      '',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'existing torrent tab handles repeated association links one dialog at a time',
    (tester) async {
      await tester.runAsync(() => tabs.close());
      tabs = TabManagerBloc()..add(AddTab(path: '#torrents'));
      await mount(tester);
      final existing = tabs.state.activeTab!;
      final fake = service as _Service;
      const source =
          'magnet:?xt=urn:btih:1111111111111111111111111111111111111111';
      tabs.add(AddTab(path: TorrentLaunchRequest.pathFor(source)));
      await tester.pumpAndSettle();
      expect(tabs.state.tabs, hasLength(1));
      expect(tabs.state.activeTabId, existing.id);
      expect(fake.opened, [source]);
      expect(find.byType(TorrentDownloadDialog), findsOneWidget);
      tabs.add(AddTab(path: TorrentLaunchRequest.pathFor(source)));
      tabs.add(AddTab(path: TorrentLaunchRequest.pathFor('/another.torrent')));
      await tester.pumpAndSettle();
      expect(fake.opened, [source]);
      expect(tabs.state.activeTab!.pendingTorrentSources, hasLength(2));
      for (var i = 0; i < 3; i++) {
        expect(find.byType(TorrentDownloadDialog), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
      expect(fake.opened, [source, source, '/another.torrent']);
      expect(tabs.state.tabs, hasLength(1));
      expect(tabs.state.activeTab!.pendingTorrentSources, isEmpty);
      expect(fake.downloads, isEmpty);
      expect(find.byType(TorrentDownloadDialog), findsNothing);
      expect(find.byType(SearchTextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('startup requests wait for the torrent library to initialize', (
    tester,
  ) async {
    await tester.runAsync(() => tabs.close());
    tabs = TabManagerBloc();
    const source =
        'magnet:?xt=urn:btih:2222222222222222222222222222222222222222';
    tabs.add(AddTab(path: TorrentLaunchRequest.pathFor(source)));
    tabs.add(AddTab(path: TorrentLaunchRequest.pathFor('/startup.torrent')));
    await mount(tester);
    expect(tabs.state.tabs, hasLength(1));
    expect((service as _Service).opened, [source]);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect((service as _Service).opened, [source, '/startup.torrent']);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tabs.state.activeTab!.pendingTorrentSources, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('magnet switches from another tab without awaiting a slow page', (
    tester,
  ) async {
    await tester.runAsync(() => tabs.close());
    tabs = TabManagerBloc()..add(AddTab(path: '#torrents'));
    await mount(tester, tabbed: true);
    final torrentId = tabs.state.activeTabId;
    tabs.add(AddTab(path: '#home'));
    await tester.pumpAndSettle();
    expect(find.text('Other tab'), findsOneWidget);
    final slowPage = repo.held[''] = Completer<TorrentPage>();
    const source =
        'magnet:?xt=urn:btih:3333333333333333333333333333333333333333';
    tabs.add(AddTab(path: TorrentLaunchRequest.pathFor(source)));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(tabs.state.activeTabId, torrentId);
    expect(tabs.state.tabs, hasLength(2));
    expect((service as _Service).opened, [source]);
    expect(find.byType(TorrentDownloadDialog), findsOneWidget);
    expect(slowPage.isCompleted, isFalse);
    slowPage.complete(const TorrentPage([], 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('startup magnet dialog does not await the initial library page', (
    tester,
  ) async {
    await tester.runAsync(() => tabs.close());
    tabs = TabManagerBloc()..add(AddTab(path: '#torrents'));
    final slowPage = repo.held[''] = Completer<TorrentPage>();
    const source =
        'magnet:?xt=urn:btih:4444444444444444444444444444444444444444';
    tabs.add(AddTab(path: TorrentLaunchRequest.pathFor(source)));
    await mount(tester, settle: false);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect((service as _Service).opened, [source]);
    expect(find.byType(TorrentDownloadDialog), findsOneWidget);
    expect(slowPage.isCompleted, isFalse);
    slowPage.complete(const TorrentPage([], 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'association activation shows existing destination without creating another task',
    (tester) async {
      await (await SharedPreferences.getInstance()).setBool(
        'torrent.startImmediately',
        false,
      );
      await mount(tester, initialSource: 'magnet:?xt=urn:btih:${'0' * 40}');
      expect((service as _Service).opened, ['magnet:?xt=urn:btih:${'0' * 40}']);
      expect(find.byType(TorrentDownloadDialog), findsOneWidget);
      final field = tester.widget<CbTextField>(
        find.byKey(const ValueKey('torrent-download-destination')),
      );
      expect(field.readOnly, isTrue);
      expect(
        tester
            .widget<TorrentDownloadDialog>(find.byType(TorrentDownloadDialog))
            .startImmediately,
        isTrue,
      );
      expect(
        tester
            .widget<CbButton>(
              find.byKey(const ValueKey('torrent-download-browse')),
            )
            .onPressed,
        isNull,
      );
      expect(
        field.controller!.text,
        p.join(Directory.systemTemp.path, 'existing-downloads'),
      );
      expect((service as _Service).downloads, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('1–80 of 180 torrents'), findsOneWidget);
      expect(find.byType(SearchTextField), findsNothing);
      expect(repo.queries, everyElement(''));
      expect(tester.takeException(), isNull);
    },
  );

  for (final startImmediately in [true, false]) {
    testWidgets(
      'opening a torrent confirms destination and immediate start $startImmediately',
      (tester) async {
        final fake = service as _Service;
        fake.openStatus = 'library';
        await mount(
          tester,
          width: 390,
          locale: 'vi',
          initialSource: '/new.torrent',
        );
        expect(find.byType(TorrentDownloadDialog), findsOneWidget);
        expect(fake.downloads, isEmpty);
        final destination = p.join(Directory.systemTemp.path, 'chosen-payload');
        final field = tester.widget<CbTextField>(
          find.byKey(const ValueKey('torrent-download-destination')),
        );
        field.controller!.text = destination;
        if (!startImmediately) {
          await tester.tap(
            find.byKey(const ValueKey('torrent-start-immediately')),
          );
          await tester.pumpAndSettle();
        }
        await tester.tap(
          find.byKey(const ValueKey('torrent-download-confirm')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(TorrentDownloadDialog), findsNothing);
        expect(fake.downloads, [('0' * 40, destination, startImmediately)]);
        expect(
          (await SharedPreferences.getInstance()).getBool(
            'torrent.startImmediately',
          ),
          startImmediately,
        );
        expect(
          (await SharedPreferences.getInstance()).getString(
            'torrent.lastDownloadDirectory',
          ),
          destination,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'cancelling open or providing a relative folder never starts downloading',
    (tester) async {
      final fake = service as _Service;
      fake.openStatus = 'library';
      await mount(tester, initialSource: '/new.torrent');
      final field = tester.widget<CbTextField>(
        find.byKey(const ValueKey('torrent-download-destination')),
      );
      field.controller!.text = 'relative-path';
      await tester.tap(find.byKey(const ValueKey('torrent-download-confirm')));
      await tester.pumpAndSettle();
      expect(
        find.text('Choose or enter an absolute download folder path.'),
        findsOneWidget,
      );
      expect(fake.downloads, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(TorrentDownloadDialog), findsNothing);
      expect(fake.downloads, isEmpty);
      expect(find.text('1–80 of 180 torrents'), findsOneWidget);
      expect(find.byType(SearchTextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saving without downloading remembers the choice on the next open',
    (tester) async {
      final fake = service as _Service;
      fake.openStatus = 'library';
      await mount(tester, initialSource: '/first.torrent');
      await tester.tap(find.byKey(const ValueKey('torrent-start-immediately')));
      await tester.tap(find.byKey(const ValueKey('torrent-download-confirm')));
      await tester.pumpAndSettle();
      expect(fake.downloads.single.$3, isFalse);
      final savedDirectory = fake.downloads.single.$2;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mount(tester, initialSource: '/second.torrent');
      expect(
        tester
            .widget<TorrentDownloadDialog>(find.byType(TorrentDownloadDialog))
            .startImmediately,
        isFalse,
      );
      expect(
        tester
            .widget<CbTextField>(
              find.byKey(const ValueKey('torrent-download-destination')),
            )
            .controller!
            .text,
        savedDirectory,
      );
      await tester.tap(find.byKey(const ValueKey('torrent-download-confirm')));
      await tester.pumpAndSettle();
      expect(fake.downloads, hasLength(2));
      expect(fake.downloads.last.$3, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('paused torrent can browse a new directory and stay paused', (
    tester,
  ) async {
    final fake = service as _Service;
    fake.openStatus = 'paused';
    final originalPicker = FilePickerPlatform.instance;
    final picker = _DirectoryPicker()
      ..selection = p.join(Directory.systemTemp.path, 'chosen-new-download');
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = originalPicker);
    await mount(
      tester,
      width: 390,
      locale: 'vi',
      initialSource: '/paused.torrent',
    );
    final field = tester.widget<CbTextField>(
      find.byKey(const ValueKey('torrent-download-destination')),
    );
    expect(field.readOnly, isFalse);
    field.controller!.text = p.join(
      Directory.systemTemp.path,
      'missing-parent-${DateTime.now().microsecondsSinceEpoch}',
      'child',
    );
    await _browseDownloadFolder(tester, picker);
    expect(picker.calls, 1);
    expect(picker.initial, p.normalize(Directory.systemTemp.path));
    expect(picker.parentLocked, isTrue);
    expect(field.controller!.text, picker.selection);
    await tester.tap(find.byKey(const ValueKey('torrent-download-confirm')));
    await tester.pumpAndSettle();
    expect(fake.downloads, [('0' * 40, picker.selection!, false)]);
    expect(fake.resumed, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cancelling the folder picker keeps the destination and start preference',
    (tester) async {
      final fake = service as _Service;
      fake.openStatus = 'library';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('torrent.startImmediately', false);
      final originalPicker = FilePickerPlatform.instance;
      final picker = _DirectoryPicker();
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = originalPicker);
      await mount(tester, initialSource: '/cancel-picker.torrent');
      final field = tester.widget<CbTextField>(
        find.byKey(const ValueKey('torrent-download-destination')),
      );
      field.controller!.text = Directory.systemTemp.path;
      await _browseDownloadFolder(tester, picker);
      expect(picker.calls, 1);
      expect(field.controller!.text, Directory.systemTemp.path);
      await tester.tap(find.byKey(const ValueKey('torrent-start-immediately')));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(prefs.getBool('torrent.startImmediately'), isFalse);
      expect(fake.downloads, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('existing active torrent can be paused from its open dialog', (
    tester,
  ) async {
    final fake = service as _Service;
    await mount(tester, initialSource: 'magnet:?xt=urn:btih:${'0' * 40}');
    await tester.tap(find.byKey(const ValueKey('torrent-start-immediately')));
    await tester.tap(find.byKey(const ValueKey('torrent-download-confirm')));
    await tester.pumpAndSettle();
    expect(fake.downloads, isEmpty);
    expect(fake.paused, ['0' * 40]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'F5 and toolbar refresh import new sources before loading the index',
    (tester) async {
      await mount(tester);
      final fake = service as _Service;
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pumpAndSettle();
      expect(fake.importRefreshes, 1);
      expect(fake.syncs, 0);
      expect(find.text('Torrent 180.mp4'), findsOneWidget);
      expect(find.text('1–80 of 181 torrents'), findsOneWidget);
      final refresh = find.byKey(const ValueKey('shared-refresh-action'));
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(fake.importRefreshes, 2);
      expect(fake.syncs, 0);
      expect(find.text('Torrent 181.mp4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('scan and F5 share a single loading indicator', (tester) async {
    await mount(tester);
    final fake = service as _Service;
    final loading = find.byWidgetPredicate(
      (widget) => widget is LinearProgressIndicator && widget.value == null,
    );
    expect(loading, findsNothing);

    fake.scan = const TorrentScanProgress(running: true, visited: 1);
    final queriesBeforeScan = repo.queries.length;
    fake.emitChange();
    await tester.pump(const Duration(milliseconds: 850));
    expect(loading, findsOneWidget);
    expect(repo.queries.length, queriesBeforeScan);

    fake.refreshGate = Completer<void>();
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pump();
    expect(loading, findsOneWidget);

    fake.scan = const TorrentScanProgress(visited: 1);
    fake.emitChange();
    await tester.pump();
    expect(loading, findsOneWidget);

    fake.refreshGate!.complete();
    await tester.pumpAndSettle();
    expect(loading, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'repeated F5 coalesces imports and torrent commands stay one row below the shared browser bar',
    (tester) async {
      await mount(tester);
      final fake = service as _Service;
      fake.refreshGate = Completer<void>();
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pump();
      expect(fake.importRefreshes, 1);
      fake.refreshGate!.complete();
      await tester.pumpAndSettle();
      for (final width in [1100.0, 390.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        final toolbar = find.byKey(const ValueKey('torrent-toolbar'));
        final surface = tester.widget<BrowserLikeFileSurface>(
          find.byType(BrowserLikeFileSurface),
        );
        expect(surface.pathNavigationBar, isA<PathNavigationBar>());
        expect(surface.actions, isNotEmpty);
        expect(find.byType(CbSelect<String>), findsNothing);
        final browserY = tester
            .getCenter(find.byKey(const ValueKey('shared-view-mode-menu')))
            .dy;
        expect(
          tester
              .getCenter(find.byKey(const ValueKey('shared-refresh-action')))
              .dy,
          browserY,
        );
        final positions = [
          tester
              .getCenter(find.byKey(const ValueKey('torrent-import-action')))
              .dy,
          tester
              .getCenter(
                find.byKey(const ValueKey('torrent-scan-folder-action')),
              )
              .dy,
          tester
              .getCenter(find.byKey(const ValueKey('torrent-filter-menu')))
              .dy,
        ];
        expect(positions.toSet(), hasLength(1));
        expect(positions.first, greaterThan(browserY));
        expect(
          find.descendant(
            of: toolbar,
            matching: find.byKey(const ValueKey('shared-view-mode-menu')),
          ),
          findsNothing,
        );
        expect(tester.getSize(toolbar).height, lessThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final link in [
    'https://example.com/download?id=1',
    'magnet:?xt=urn:btih:${'0' * 40}',
  ]) {
    testWidgets('link button opens destination options for $link', (
      tester,
    ) async {
      final fake = service as _Service;
      fake.openStatus = 'library';
      await mount(tester, width: 390, locale: 'vi');
      final button = find.byKey(const ValueKey('torrent-add-link-action'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Thêm torrent bằng link'), findsWidgets);
      final input = tester.widget<CbTextField>(
        find.byKey(const ValueKey('torrent-link-input')),
      );
      input.controller!.text = link;
      await tester.tap(find.byKey(const ValueKey('torrent-link-confirm')));
      await tester.pumpAndSettle();
      expect(fake.links, [link]);
      expect(find.byType(TorrentLinkDialog), findsNothing);
      expect(find.byType(TorrentDownloadDialog), findsOneWidget);
      expect(fake.downloads, isEmpty);
      await tester.tap(find.text('Hủy bỏ'));
      await tester.pumpAndSettle();
      expect(find.text('1–80 / 180 torrent'), findsOneWidget);
      expect(find.byType(SearchTextField), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
    'invalid links stay editable in the add dialog and cancel starts no download',
    (tester) async {
      await mount(tester);
      final button = find.byKey(const ValueKey('torrent-add-link-action'));
      await tester.tap(button);
      await tester.pumpAndSettle();
      final input = tester.widget<CbTextField>(
        find.byKey(const ValueKey('torrent-link-input')),
      );
      input.controller!.text = 'bad-link';
      await tester.tap(find.byKey(const ValueKey('torrent-link-confirm')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Invalid torrent link'), findsOneWidget);
      expect(input.controller!.text, 'bad-link');
      expect(find.byType(TorrentDownloadDialog), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(TorrentLinkDialog), findsNothing);
      expect((service as _Service).downloads, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pages through a large index without building every row', (
    tester,
  ) async {
    await (await SharedPreferences.getInstance()).setString(
      'torrent.sortOption',
      'nameAsc',
    );
    await mount(tester);
    expect(find.text('1–80 of 180 torrents'), findsOneWidget);
    expect(repo.lastSort, SortOption.dateDesc);
    expect(find.text('Torrent 179.mp4'), findsOneWidget);
    expect(find.text('Torrent 0.mp4'), findsNothing);
    // Locate by tooltip rather than depending on the icon font implementation.
    final button = find.byWidgetPredicate(
      (w) => w is CbButton && w.tooltip == 'Next Page',
    );
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('81–160 of 180 torrents'), findsOneWidget);
    expect(find.text('Torrent 99.mp4'), findsOneWidget);
    expect(find.text('Torrent 179.mp4'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('live search ignores selection changes and drops stale replies', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('shared-search-action')));
    await tester.pumpAndSettle();
    final field = tester.widget<SearchTextField>(
      find.byType(SearchTextField).first,
    );
    final controller = field.controller! as SearchTextController;
    final originalQueries = repo.queries.length;
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(repo.queries.length, originalQueries);
    repo.held['old'] = Completer<TorrentPage>();
    controller.text = 'old';
    await tester.pump(const Duration(milliseconds: 300));
    controller.text = 'Torrent 17';
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('1–11 of 11 torrents'), findsOneWidget);
    repo.held['old']!.complete(const TorrentPage([], 0));
    await tester.pumpAndSettle();
    expect(find.text('1–11 of 11 torrents'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final confirm in [false, true]) {
    testWidgets(
      'copy to move previews sources and requires confirmation $confirm',
      (tester) async {
        final fake = service as _Service;
        fake.configuredMode = 'copy';
        fake.configuredDirectory = r'C:\archive';
        fake.cleanupSources = List.generate(1200, (index) {
          final hash = index.toRadixString(16).padLeft(40, '0');
          return TorrentMoveSource(
            path:
                r'C:\qBittorrent\BT_backup\'
                '$hash.torrent',
            destination:
                r'C:\archive\00\'
                '$hash.torrent',
            hash: hash,
            modified: 1,
            size: 100,
          );
        });
        await mount(tester, width: confirm ? 390 : 1100, locale: 'vi');
        final settings = find.byWidgetPredicate(
          (w) => w is CbButton && w.tooltip == 'Cài đặt',
        );
        await tester.ensureVisible(settings);
        await tester.tap(settings);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sao chép về thư mục đã chọn'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Di chuyển về thư mục đã chọn'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('torrent-move-confirmation')),
          findsOneWidget,
        );
        expect(find.text(fake.cleanupSources.first.path), findsOneWidget);
        expect(find.textContaining('1200 file .torrent'), findsOneWidget);
        expect(fake.configuredMode, 'copy');
        expect(fake.appliedMove, isNull);
        // The complete approved list is accessible without building 1200 rows.
        expect(find.byType(SelectableText).evaluate().length, lessThan(40));
        await tester.tap(
          find.byKey(
            ValueKey(confirm ? 'torrent-move-confirm' : 'torrent-move-cancel'),
          ),
        );
        await tester.pumpAndSettle();
        expect(fake.configuredMode, confirm ? 'move' : 'copy');
        expect(fake.appliedMove, confirm ? same(fake.shownMove) : isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('narrow Vietnamese screen and organization settings fit', (
    tester,
  ) async {
    await mount(tester, width: 390, locale: 'vi');
    expect(
      tester
          .widget<CbButton>(find.byKey(const ValueKey('torrent-import-action')))
          .label,
      'Nhập',
    );
    await tester.tap(find.byKey(const ValueKey('torrent-import-action')));
    await tester.pumpAndSettle();
    expect(find.text('Nhập .torrent'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final settings = find.byWidgetPredicate(
      (w) => w is CbButton && w.tooltip == 'Cài đặt',
    );
    await tester.ensureVisible(settings);
    await tester.tap(settings);
    await tester.pumpAndSettle();
    expect(find.text('Chỉ index, giữ file gốc'), findsOneWidget);
    expect(find.text('Sắp xếp file torrent'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'shared view menu renders every supported layout and remembers it',
    (tester) async {
      await mount(tester);
      for (final width in [1100.0, 390.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        for (final mode in [
          ViewMode.grid,
          ViewMode.tiles,
          ViewMode.details,
          ViewMode.list,
          ViewMode.tree,
          ViewMode.columns,
        ]) {
          await tester.ensureVisible(
            find.byKey(const ValueKey('shared-view-mode-menu')),
          );
          await tester.tap(find.byKey(const ValueKey('shared-view-mode-menu')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byWidgetPredicate(
              (w) => w is PopupMenuItem<ViewMode> && w.value == mode,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<BrowserLikeFileSurface>(
                  find.byType(BrowserLikeFileSurface),
                )
                .viewMode,
            mode,
          );
          final type = switch (mode) {
            ViewMode.grid => FileGridItem,
            ViewMode.details => FileDetailsItem,
            ViewMode.tree => FileTreeView,
            ViewMode.columns => MillerColumnsView,
            _ => FileItem,
          };
          expect(find.byType(type), findsWidgets);
          if (mode == ViewMode.details) {
            expect(
              find.descendant(
                of: find.byType(FileDetailsItem).first,
                matching: find.byWidgetPredicate(
                  (w) => w is OptimizedFileIcon && w.size == 24,
                ),
              ),
              findsOneWidget,
            );
            expect(find.byTooltip('Column settings'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        }
      }
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('torrent.viewMode'), 'columns');
      await prefs.setString('torrent.viewMode', 'details');
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester);
      expect(find.byType(FileDetailsItem), findsWidgets);
    },
  );

  testWidgets(
    'sort resets pagination, persists and details headings toggle direction',
    (tester) async {
      await mount(tester);
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is CbButton && w.tooltip == 'Next Page',
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.lastOffset, 80);
      await tester.tap(find.byKey(const ValueKey('shared-sort-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Size (Largest First)'));
      await tester.pumpAndSettle();
      expect(repo.lastSort, SortOption.sizeDesc);
      expect(repo.lastOffset, 0);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'torrent.browserSortOption',
        ),
        'sizeDesc',
      );
      await tester.tap(find.byKey(const ValueKey('shared-view-mode-menu')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is PopupMenuItem<ViewMode> && w.value == ViewMode.details,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Size'));
      await tester.tap(find.text('Size'));
      await tester.pumpAndSettle();
      expect(repo.lastSort, SortOption.sizeAsc);
      await tester.tap(find.text('Size'));
      await tester.pumpAndSettle();
      expect(repo.lastSort, SortOption.sizeDesc);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Ctrl+F preserves the query, regex toggle applies live, Escape clears search',
    (tester) async {
      await mount(tester, width: 390);
      Future<void> ctrlF() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }

      await ctrlF();
      expect(find.byType(SearchTextField), findsOneWidget);
      final controller = tester
          .widget<SearchTextField>(find.byType(SearchTextField))
          .controller!;
      controller.text = 'Torrent 17';
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await ctrlF();
      expect(controller.text, 'Torrent 17');
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is CbTooltip && w.message == 'Regex mode',
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(repo.lastRegex, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SearchTextField), findsNothing);
      expect(repo.queries.last, '');
      expect(repo.lastRegex, isFalse);
      expect(find.text('1–80 of 180 torrents'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact items retain torrent operations in their menu', (
    tester,
  ) async {
    await mount(tester);
    final extension = tester.widget<FileContextMenuExtension>(
      find.byType(FileContextMenuExtension),
    );
    final sections = extension.sections(
      tester.element(find.byType(FileItem).first),
      ['/179.torrent'],
    );
    final labels = sections
        .expand((section) => section.actions)
        .map((a) => a.label)
        .toList();
    expect(
      labels,
      containsAll([
        'Download to…',
        'Copy magnet link',
        'Torrents · Properties',
        'Remove from index',
      ]),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'context menu copies magnets for local torrents and multiple selection',
    (tester) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await mount(tester);
      final extension = tester.widget<FileContextMenuExtension>(
        find.byType(FileContextMenuExtension),
      );
      final context = tester.element(find.byType(FileItem).first);
      for (final paths in [
        ['/179.torrent'],
        ['/179.torrent', '/178.torrent'],
      ]) {
        final action = extension
            .sections(context, paths)
            .expand((s) => s.actions)
            .singleWhere((a) => a.id == 'torrent_copy_magnet');
        expect(action.label, 'Copy magnet link');
        await action.onSelected!(context);
        final links = clipboard!.split('\n').map(MagnetLink.parse).toList();
        expect(
          links.map((link) => link.name),
          paths.map(
            (path) => 'Torrent ${p.basenameWithoutExtension(path)}.mp4',
          ),
        );
        expect(
          links.map((link) => link.hash),
          paths.map(
            (path) => p.basenameWithoutExtension(path).padLeft(40, '0'),
          ),
        );
      }
      expect((service as _Service).downloads, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('opening a new source preserves the current search and page', (
    tester,
  ) async {
    (service as _Service).openStatus = 'library';
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('shared-search-action')));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<SearchTextField>(find.byType(SearchTextField))
        .controller!;
    controller.text = 'Torrent';
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate((w) => w is CbButton && w.tooltip == 'Next Page'),
    );
    await tester.pumpAndSettle();
    expect(repo.lastOffset, 80);
    await tester.tap(find.byKey(const ValueKey('torrent-add-link-action')));
    await tester.pumpAndSettle();
    tester
            .widget<CbTextField>(
              find.byKey(const ValueKey('torrent-link-input')),
            )
            .controller!
            .text =
        'https://example.com/new.torrent';
    await tester.tap(find.byKey(const ValueKey('torrent-link-confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(TorrentDownloadDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.text, 'Torrent');
    expect(repo.queries.last, 'Torrent');
    expect(repo.lastOffset, 80);
    expect(find.text('81–160 of 180 torrents'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final accept in [false, true]) {
    testWidgets(
      'duplicate link requires merge approval $accept and can be revealed without filtering',
      (tester) async {
        final fake = service as _Service;
        fake.duplicate = true;
        fake.openStatus = 'paused';
        await mount(tester, width: 390, locale: 'vi');
        final add = find.byKey(const ValueKey('torrent-add-link-action'));
        await tester.ensureVisible(add);
        await tester.tap(add);
        await tester.pumpAndSettle();
        tester
                .widget<CbTextField>(
                  find.byKey(const ValueKey('torrent-link-input')),
                )
                .controller!
                .text =
            'magnet:?xt=urn:btih:${'0' * 40}';
        await tester.tap(find.byKey(const ValueKey('torrent-link-confirm')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('torrent-duplicate-dialog')),
          findsOneWidget,
        );
        expect(fake.mergeApprovals, 0);
        expect(fake.downloads, isEmpty);
        await tester.tap(
          find.byKey(
            ValueKey(accept ? 'torrent-merge-confirm' : 'torrent-merge-cancel'),
          ),
        );
        await tester.pumpAndSettle();
        expect(fake.mergeApprovals, accept ? 1 : 0);
        expect(find.byType(TorrentLinkDialog), findsNothing);
        if (accept) {
          expect(find.byType(TorrentDownloadDialog), findsOneWidget);
          await tester.tap(find.text('Hủy bỏ'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('torrent-reveal-recent')));
          await tester.pumpAndSettle();
          expect(repo.lastOffset, 160);
          expect(find.text('161–180 / 180 torrent'), findsOneWidget);
          expect(find.text('Torrent 0.mp4'), findsOneWidget);
          expect(find.byType(SearchTextField), findsNothing);
          expect(
            tester
                .widget<BrowserLikeFileSurface>(
                  find.byType(BrowserLikeFileSurface),
                )
                .selectionState
                .selectedFilePaths,
            {'/0.torrent'},
          );
        } else {
          expect(find.byType(TorrentDownloadDialog), findsNothing);
          expect(find.text('1–80 / 180 torrent'), findsOneWidget);
        }
        expect(fake.downloads, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'browser selection, range selection, keyboard and pagination stay consistent',
    (tester) async {
      await mount(tester);
      SelectionState selection() => tester
          .widget<BrowserLikeFileSurface>(find.byType(BrowserLikeFileSurface))
          .selectionState;
      await tester.tap(find.text('Torrent 179.mp4'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(selection().selectedFilePaths, {'/179.torrent'});
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.text('Torrent 178.mp4'), warnIfMissed: false);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(selection().selectedFilePaths, {'/179.torrent', '/178.torrent'});
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.text('Torrent 176.mp4'), warnIfMissed: false);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(selection().selectedFilePaths, {
        '/178.torrent',
        '/177.torrent',
        '/176.torrent',
      });
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(selection().selectedFilePaths, hasLength(80));
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is CbButton && w.tooltip == 'Next Page',
        ),
      );
      await tester.pumpAndSettle();
      expect(selection().selectedFilePaths, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(selection().selectedFilePaths, {'/98.torrent'});
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT, character: 'T');
      await tester.pumpAndSettle();
      expect(selection().selectedFilePaths, {'/99.torrent'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('page size changes reset the page and selection, and persist', (
    tester,
  ) async {
    await mount(tester, width: 390, locale: 'vi');
    expect(repo.lastLimit, 80);
    await tester.tap(
      find.byWidgetPredicate((w) => w is CbButton && w.tooltip == 'Trang sau'),
    );
    await tester.pumpAndSettle();
    expect(repo.lastOffset, 80);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<BrowserLikeFileSurface>(find.byType(BrowserLikeFileSurface))
          .selectionState
          .selectedFilePaths,
      isNotEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('torrent-page-size')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('50'));
    await tester.pumpAndSettle();
    expect(repo.lastLimit, 50);
    expect(repo.lastOffset, 0);
    expect(
      tester
          .widget<BrowserLikeFileSurface>(find.byType(BrowserLikeFileSurface))
          .selectionState
          .selectedFilePaths,
      isEmpty,
    );
    expect(
      (await SharedPreferences.getInstance()).getInt('torrent.pageSize'),
      50,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(
      find.byWidgetPredicate((w) => w is CbButton && w.tooltip == 'Trang sau'),
    );
    await tester.pumpAndSettle();
    expect(repo.lastOffset, 50);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await mount(tester);
    expect(repo.lastLimit, 50);
    expect(repo.lastOffset, 0);
    expect(
      tester
          .widget<CbSelect<int>>(
            find.byKey(const ValueKey('torrent-page-size')),
          )
          .value,
      50,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'large page size is passed to the query and disables the last page',
    (tester) async {
      repo.count = 1250;
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('torrent-page-size')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1000'));
      await tester.pumpAndSettle();
      expect(repo.lastLimit, 1000);
      expect(find.text('1–1000 of 1250 torrents'), findsOneWidget);
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is CbButton && w.tooltip == 'Next Page',
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.lastOffset, 1000);
      expect(find.text('1001–1250 of 1250 torrents'), findsOneWidget);
      expect(
        tester
            .widget<CbButton>(
              find.byWidgetPredicate(
                (w) => w is CbButton && w.tooltip == 'Next Page',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Details column dialog and preview use the browser controls and persist',
    (tester) async {
      await (await SharedPreferences.getInstance()).setString(
        'torrent.viewMode',
        'details',
      );
      await mount(tester);
      await tester.ensureVisible(find.byTooltip('Column settings'));
      await tester.tap(find.byTooltip('Column settings'));
      await tester.pumpAndSettle();
      final sizeToggle = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(CheckboxListTile, 'Size'),
      );
      await tester.tap(sizeToggle);
      await tester.tap(find.text('APPLY'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FileDetailsItem>(find.byType(FileDetailsItem).first)
            .columnVisibility
            .size,
        isFalse,
      );
      await tester.ensureVisible(find.byTooltip('Show preview'));
      await tester.tap(find.byTooltip('Show preview'));
      await tester.pumpAndSettle();
      expect(find.byType(FilePreviewPane), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getBool('torrent.preview'),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester);
      expect(
        tester
            .widget<FileDetailsItem>(find.byType(FileDetailsItem).first)
            .columnVisibility
            .size,
        isFalse,
      );
      expect(find.byType(FilePreviewPane), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'torrent Details show live network columns in a horizontal table',
    (tester) async {
      await (await SharedPreferences.getInstance()).setString(
        'torrent.viewMode',
        'details',
      );
      repo.taskStatus = 'active';
      repo.completedBytes = 20;
      repo.seeders = 3;
      repo.connections = 8;
      await mount(tester, width: 390);
      expect(find.byType(FileDetailsItem), findsWidgets);
      expect(find.text('Download status'), findsOneWidget);
      expect(find.text('Seeds'), findsOneWidget);
      expect(find.text('Peers'), findsOneWidget);
      String cell(String id) => tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(ValueKey('details-cell-$id-/179.torrent')),
              matching: find.byType(Text),
            ),
          )
          .data!;
      expect(cell('seeds'), '3');
      expect(cell('peers'), '8');
      expect(cell('progress'), '20.0%');
      final horizontal = find.descendant(
        of: find.byType(FileDetailsViewport),
        matching: find.byType(SingleChildScrollView),
      );
      expect(
        tester.widget<SingleChildScrollView>(horizontal).controller!.offset,
        0,
      );
      final viewport = tester.getRect(find.byType(FileDetailsViewport));
      await tester.dragFrom(
        viewport.bottomLeft + const Offset(24, -3),
        const Offset(200, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<SingleChildScrollView>(horizontal).controller!.offset,
        greaterThan(0),
      );
      repo.seeders = 0;
      repo.connections = null;
      repo.completedBytes = 80;
      (service as _Service).emitChange();
      await tester.pump(const Duration(milliseconds: 750));
      await tester.pumpAndSettle();
      expect(cell('seeds'), '0');
      expect(cell('peers'), '—');
      expect(cell('progress'), '80.0%');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('torrent column toggles apply together and persist on remount', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('torrent.viewMode', 'details');
    await mount(tester);
    await tester.tap(find.byTooltip('Column settings'));
    await tester.pumpAndSettle();
    for (final label in ['Seeds', 'Upload speed']) {
      final toggle = find.widgetWithText(CheckboxListTile, label);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('APPLY'));
    await tester.pumpAndSettle();
    expect(find.text('Seeds'), findsNothing);
    expect(find.text('Upload speed'), findsOneWidget);
    expect(find.text('Download folder'), findsOneWidget);
    expect(
      prefs.getStringList('torrent.detailColumns'),
      containsAll(['upSpeed', 'destination']),
    );
    expect(
      prefs.getStringList('torrent.detailColumns'),
      isNot(contains('seeds')),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await mount(tester);
    expect(find.text('Seeds'), findsNothing);
    expect(find.text('Upload speed'), findsOneWidget);
    // Header context menu uses the same visibility state as the dialog.
    await tester.tap(
      find.text('Download status'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    final seeds = find.widgetWithText(PopupMenuItem<String>, 'Seeds');
    await tester.ensureVisible(seeds);
    await tester.tap(seeds);
    await tester.pumpAndSettle();
    expect(prefs.getStringList('torrent.detailColumns'), contains('seeds'));
    expect(find.text('Seeds'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selected torrent progress remains live above the shared file view',
    (tester) async {
      repo.taskStatus = 'active';
      repo.completedBytes = 20;
      await mount(tester);
      await tester.tap(find.text('Torrent 179.mp4'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.textContaining('20.0%'), findsOneWidget);
      repo.completedBytes = 80;
      (service as _Service).emitChange();
      await tester.pump(const Duration(milliseconds: 750));
      await tester.pumpAndSettle();
      expect(find.textContaining('80.0%'), findsOneWidget);
      expect(find.textContaining('20.0%'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
