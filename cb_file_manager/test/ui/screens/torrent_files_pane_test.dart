import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/services/torrent/torrent_entry.dart';
import 'package:cb_file_manager/services/torrent/torrent_metainfo.dart';
import 'package:cb_file_manager/services/torrent/torrent_repository.dart';
import 'package:cb_file_manager/services/torrent/torrent_service.dart';
import 'package:cb_file_manager/ui/screens/torrent/torrent_files_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/sqlite_api.dart';

class _Db extends Fake implements Database {}

class _Service extends TorrentService {
  _Service(SharedPreferences prefs)
    : super.forTesting(
        repository: TorrentRepository(_Db()),
        preferences: prefs,
        stateDirectory: '/state',
      );

  final fetched = <String>[];
  final cancelled = <String>[];
  final fetching = <String>{};
  final errors = <String, String>{};

  @override
  Future<List<TorrentFileItem>> files(TorrentEntry entry) async => const [
    TorrentFileItem(1, 'S01/e1.mkv', 3),
    TorrentFileItem(2, 'e2.mkv', 2),
  ];

  @override
  bool isFetchingMetadata(String hash) => fetching.contains(hash);
  @override
  String? metadataError(String hash) => errors[hash];
  @override
  Future<void> fetchMetadata(TorrentEntry entry) async =>
      fetched.add(entry.hash);
  @override
  Future<void> cancelMetadata(String hash) async => cancelled.add(hash);
}

TorrentEntry _entry({String path = '/show.torrent'}) => TorrentEntry.fromMap({
  'hash': 'a' * 40,
  'name': 'Show',
  'torrent_path': path,
  'source_uri': path.isEmpty ? 'magnet:?xt=urn:btih:${'a' * 40}' : null,
  'category': 'video',
  'group_name': '',
  'total_bytes': 5,
  'file_count': 2,
  'status': 'paused',
  'completed_bytes': 0,
  'download_speed': 0,
});

void main() {
  late _Service service;
  var closed = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service = _Service(await SharedPreferences.getInstance());
    closed = 0;
  });

  Future<void> pump(WidgetTester tester, TorrentEntry? entry) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('vi')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: CbThemeBuilder.build(
          brightness: Brightness.light,
          accent: Colors.teal,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: TorrentFilesPane(
              service: service,
              entry: entry,
              height: 240,
              onResize: (_) {},
              onResizeEnd: () {},
              onClose: () => closed++,
              formatSize: (bytes) => '$bytes B',
              canFetchMetadata: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('lists the files of the selected torrent', (tester) async {
    await pump(tester, _entry());
    expect(find.text('Files in torrent'), findsOneWidget);
    expect(find.text('2 files · 5 B'), findsOneWidget);
    expect(find.text('S01/e1.mkv', findRichText: true), findsOneWidget);
    expect(find.text('e2.mkv', findRichText: true), findsOneWidget);
    expect(find.text('3 B'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('torrent-files-pane-close')));
    expect(closed, 1);
  });

  testWidgets('asks to select one torrent when none is selected', (
    tester,
  ) async {
    await pump(tester, null);
    expect(find.text('Select one torrent to see its files.'), findsOneWidget);
  });

  testWidgets('magnet without metadata offers to fetch its file list', (
    tester,
  ) async {
    final magnet = _entry(path: '');
    await pump(tester, magnet);
    expect(find.textContaining('have not been fetched yet'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('torrent-fetch-metadata')));
    expect(service.fetched, [magnet.hash]);

    service.fetching.add(magnet.hash);
    await pump(tester, magnet);
    expect(
      find.text('Fetching the name and file list from peers…'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('torrent-cancel-metadata')));
    expect(service.cancelled, [magnet.hash]);

    service.fetching.clear();
    service.errors[magnet.hash] = 'no peers';
    await pump(tester, magnet);
    expect(
      find.text('Could not fetch the file list: no peers'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });
}
