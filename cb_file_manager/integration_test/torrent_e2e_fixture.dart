// Real SQLite, metainfo files, loopback HTTP, aria2 and window IPC. Only app
// storage/discovery are isolated; no FakeEngine or mocked TorrentService.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cb_file_manager/e2e/cb_e2e_config.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/main.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:cb_file_manager/services/torrent/aria2_engine.dart';
import 'package:cb_file_manager/services/torrent/torrent_entry.dart';
import 'package:cb_file_manager/services/torrent/torrent_launch_request.dart';
import 'package:cb_file_manager/services/torrent/torrent_metainfo.dart';
import 'package:cb_file_manager/services/torrent/torrent_repository.dart';
import 'package:cb_file_manager/services/torrent/torrent_service.dart';
import 'package:cb_file_manager/services/windowing/desktop_windowing_service.dart';
import 'package:cb_file_manager/services/windowing/window_startup_payload.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/screens/torrent/torrent_screen.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'e2e_helpers.dart';
import 'e2e_sandbox_paths.dart';

Future<void> waitForTorrentCondition(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 20),
  required String reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(condition(), isTrue, reason: reason);
  await tester.pump();
}

Future<void> waitForTorrentWidget(WidgetTester tester, Finder finder) =>
    waitForTorrentCondition(
      tester,
      () => finder.evaluate().isNotEmpty,
      reason: 'Expected $finder',
    );

Uint8List encodeTorrentFixture(Object value) {
  List<int> encode(Object item) {
    if (item is int) return ascii.encode('i${item}e');
    if (item is String) return encode(Uint8List.fromList(utf8.encode(item)));
    if (item is Uint8List) return [...ascii.encode('${item.length}:'), ...item];
    if (item is List) {
      return [108, ...item.expand((v) => encode(v as Object)), 101];
    }
    if (item is Map<String, Object>) {
      final keys = item.keys.toList()..sort();
      return [
        100,
        for (final key in keys) ...[...encode(key), ...encode(item[key]!)],
        101,
      ];
    }
    throw ArgumentError.value(item);
  }

  return Uint8List.fromList(encode(value));
}

class TorrentE2EFixture {
  TorrentE2EFixture._(
    this.root,
    this.repository,
    this.engine,
    this.service,
    this.windowing,
    this.port,
  );

  final Directory root;
  final TorrentRepository repository;
  final Aria2Engine engine;
  final TorrentService service;
  final DesktopWindowingService windowing;
  final int port;
  HttpServer? _http;
  final _responses = <String, Uint8List>{};
  String get sources => p.join(root.path, 'sources');
  String get library => p.join(root.path, 'library');
  String get payload => p.join(root.path, 'payload');

  static Future<TorrentE2EFixture> create() async {
    if (!E2ESandboxPaths.isInstalled) {
      throw StateError('Install the E2E sandbox first');
    }
    final root = await Directory.systemTemp.createTemp('cb_e2e_torrent_');
    SharedPreferences.setMockInitialValues({
      'torrent.autoImport': false,
      'torrent.scanRoots': [p.join(root.path, 'sources')],
      'torrent.storageMode': 'copy',
      'torrent.libraryDirectory': p.join(root.path, 'library'),
      'torrent.qbittorrentSources': [p.join(root.path, 'qbit', 'BT_backup')],
    });
    for (final path in [
      'sources',
      'state',
      'library',
      'payload',
      'qbit/BT_backup',
    ]) {
      await Directory(p.join(root.path, path)).create(recursive: true);
    }
    final db = await SqliteDatabaseProvider().getDatabase();
    if (!p.isWithin(E2ESandboxPaths.rootPath!, db.path)) {
      throw StateError('Refusing to use a non-sandbox app database');
    }
    final repo = TorrentRepository(db);
    await repo.initialize();
    await db.delete('torrent_sources');
    await db.delete('torrents');
    final engine = Aria2Engine(enablePeerDiscovery: false);
    final service = TorrentService.forTesting(
      repository: repo,
      preferences: await SharedPreferences.getInstance(),
      stateDirectory: p.join(root.path, 'state'),
      engine: engine,
      sourceDiscovery: () async => [p.join(root.path, 'qbit', 'BT_backup')],
    );
    if (Platform.isWindows) {
      final binary = p.join(
        Directory.current.path,
        'windows',
        'aria2',
        'aria2c.exe',
      );
      if (!await File(binary).exists()) {
        throw StateError('Run just fetch-aria2 first');
      }
      await service.setExecutable(binary);
    }
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    final windowing = DesktopWindowingService.forTesting(registryPort: port);
    return TorrentE2EFixture._(root, repo, engine, service, windowing, port);
  }

  Future<void> start(WidgetTester tester, {String? path}) async {
    await UserPreferences.instance.init();
    await UserPreferences.instance.setViewMode(ViewMode.list);
    await UserPreferences.instance.setPreviewPaneVisible(false);
    CbE2EConfig.torrentService = service;
    CbE2EConfig.desktopWindowingService = windowing;
    CbE2EConfig.startupPayload = WindowStartupPayload(
      tabs: [WindowTabPayload(path: path ?? '#torrents')],
    );
    await runCbFileApp();
    if (TorrentLaunchRequest.isPath(path ?? '#torrents')) {
      await waitForTorrentWidget(tester, find.byType(TorrentScreen));
      await waitForTorrentWidget(
        tester,
        find.byKey(const ValueKey('torrent-toolbar')),
      );
    } else {
      await waitForTorrentWidget(
        tester,
        find.byKey(const ValueKey('shared-refresh-action')),
      );
    }
  }

  TabManagerBloc tabs(WidgetTester tester) =>
      tester.element(find.byType(TorrentScreen)).read<TabManagerBloc>();

  Future<void> launch(WidgetTester tester, String source) async {
    var ready = false;
    await waitForTorrentCondition(
      tester,
      () {
        // Registration is asynchronous after the app's first frame.
        unawaited(
          windowing.listWindows().then((windows) {
            ready = windows.any(
              (window) => window.windowId == windowing.windowId,
            );
          }),
        );
        return ready;
      },
      reason:
          'The test-owned window should register with its private IPC server',
    );
    final sender = DesktopWindowingService.forTesting(registryPort: port);
    expect(await sender.openTorrentSourcesInExistingWindow([source]), isTrue);
    await tester.pump();
  }

  Future<HttpServer> _server() async {
    if (_http != null) return _http!;
    final server = _http = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    server.listen((request) async {
      try {
        final data = _responses[request.uri.path];
        if (data == null) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          var start = 0;
          var end = data.length - 1;
          final range = RegExp(
            r'^bytes=(\d+)-(\d*)$',
          ).firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
          if (range != null) {
            start = int.parse(range.group(1)!);
            end = range.group(2)!.isEmpty ? end : int.parse(range.group(2)!);
            request.response.statusCode = HttpStatus.partialContent;
            request.response.headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes $start-$end/${data.length}',
            );
          }
          request.response.contentLength = end - start + 1;
          request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
          for (var offset = start; offset <= end; offset += 4096) {
            final limit = (offset + 4096).clamp(0, end + 1);
            request.response.add(data.sublist(offset, limit));
            await request.response.flush();
            if (request.uri.path.endsWith('.bin')) {
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
          }
        }
        await request.response.close();
      } on IOException {
        // A real aria2 pause/stop intentionally disconnects the web seed.
      }
    });
    return server;
  }

  Uint8List payloadBytes(String name, {int size = 512 * 1024}) =>
      Uint8List.fromList(
        List.generate(size, (i) => (i + name.codeUnitAt(0)) % 251),
      );

  Future<File> torrent(
    String name, {
    bool webSeed = false,
    String? directory,
  }) async {
    final data = payloadBytes(name);
    final pieces = <int>[];
    for (var start = 0; start < data.length; start += 16384) {
      pieces.addAll(
        sha1
            .convert(data.sublist(start, (start + 16384).clamp(0, data.length)))
            .bytes,
      );
    }
    final info = <String, Object>{
      'name': name,
      'length': data.length,
      'piece length': 16384,
      'pieces': Uint8List.fromList(pieces),
      'private': 1,
    };
    final metadata = <String, Object>{'info': info};
    if (webSeed) {
      final server = await _server();
      _responses['/$name'] = data;
      metadata['url-list'] = ['http://127.0.0.1:${server.port}/$name'];
    }
    final bytes = encodeTorrentFixture(metadata);
    final file = File(p.join(directory ?? sources, '$name.torrent'));
    await file.parent.create(recursive: true);
    return file.writeAsBytes(bytes, flush: true);
  }

  Future<String> httpTorrent(File file) async {
    final server = await _server();
    _responses['/metainfo'] = await file.readAsBytes();
    return 'http://127.0.0.1:${server.port}/metainfo';
  }

  Future<TorrentEntry> entry(File file) async => (await repository.get(
    TorrentMetainfo.parse(await file.readAsBytes()).hash,
  ))!;

  Future<TorrentEntry> waitForStatus(
    WidgetTester tester,
    String hash,
    String status,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(deadline)) {
      final entry = await repository.get(hash);
      if (entry?.status == status) return entry!;
      await tester.pump(const Duration(milliseconds: 100));
    }
    final entry = await repository.get(hash);
    fail(
      'Expected torrent $hash status $status, got ${entry?.status}: ${entry?.error}',
    );
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await windowing.dispose();
    await engine.dispose();
    service.dispose();
    await _http?.close(force: true);
    await e2eTearDown(tester, root);
  }

  Future<Map> waitForTask(
    WidgetTester tester,
    String hash,
    String status,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(deadline)) {
      final entry = await repository.get(hash);
      if (entry?.gid != null && engine.running) {
        try {
          final task = await engine.call('tellStatus', [entry!.gid]) as Map;
          if (task['status'] == status) return task;
        } on Aria2RpcException catch (error) {
          if (!error.message.contains('not found')) rethrow;
        }
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    fail('Real aria2 task $hash never reached $status');
  }
}
