import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cb_file_manager/services/torrent/torrent_download_options.dart';
import 'package:cb_file_manager/services/windowing/torrent_options_window_service.dart';
import 'package:cb_file_manager/services/windowing/window_startup_payload.dart';
import 'package:cb_file_manager/services/windowing/torrent_options_window_anchor.dart';

class _Window {
  Socket? socket;
  StreamIterator<String>? messages;
  int launches = 0;
  late Map<String, String> env;
  Completer<void> connected = Completer<void>();

  Future<void> launch({
    required String executable,
    required List<String> arguments,
    required Map<String, String> environment,
    required String workingDirectory,
  }) async {
    launches++;
    if (connected.isCompleted) connected = Completer<void>();
    env = environment;
    final client = socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      int.parse(env[TorrentOptionsWindowService.envPort]!),
    );
    messages = StreamIterator(
      client
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter()),
    );
    client.write(
      '${jsonEncode({'token': env[TorrentOptionsWindowService.envToken]})}\n',
    );
    connected.complete();
  }

  Future<Map<String, dynamic>> next() async {
    await connected.future;
    expect(
      await messages!.moveNext().timeout(const Duration(seconds: 3)),
      isTrue,
    );
    return jsonDecode(messages!.current) as Map<String, dynamic>;
  }

  void reply(Map<String, dynamic> request, Map<String, dynamic>? options) {
    socket!.write('${jsonEncode({'id': request['id'], 'options': options})}\n');
  }

  Future<void> close() async {
    socket?.destroy();
    await messages?.cancel();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Window window;
  late TorrentOptionsWindowService service;
  final destination = p.join(Directory.systemTemp.path, 'cb-payload');
  late TorrentDownloadRequest request;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    window = _Window();
    service = TorrentOptionsWindowService.forTesting(launch: window.launch);
    request = TorrentDownloadRequest(
      name: 'Example',
      initialDestination: destination,
    );
  });

  test('prepares early only when receiving with an options form', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('torrent.receiveInBackground', true);
    await service.warmUpIfNeeded();
    expect(window.launches, 0);
    await prefs.setBool('torrent.receiveInBackground', false);
    await prefs.setBool('torrent.showDownloadDialog', false);
    await service.warmUpIfNeeded();
    expect(window.launches, 0);
    // Explicit Download to remains available even with auto-receive enabled.
    final result = service.show(request);
    window.reply(await window.next(), null);
    expect(await result, isNull);
    expect(window.launches, 1);
  });

  test(
    'default preferences prepare one reusable form before a request',
    () async {
      await service.warmUpIfNeeded();
      await service.warmUpIfNeeded();
      expect(window.launches, 1);
    },
  );
  tearDown(() async {
    await service.dispose();
    await window.close();
  });

  test(
    'warms hidden and reuses one process for queued requests and cancel',
    () async {
      await service.warmUp();
      expect(
        window.env[WindowStartupPayload.envWindowRoleKey],
        'torrent-options',
      );
      expect(window.env[WindowStartupPayload.envStartHiddenKey], '1');
      final first = service.show(request);
      final second = service.show(request);
      final message = await window.next();
      expect(message['request']['name'], 'Example');
      window.reply(
        message,
        TorrentDownloadOptions(destination, false).toJson(),
      );
      expect((await first)!.startImmediately, isFalse);
      final next = await window.next();
      expect(next['id'], isNot(message['id']));
      window.reply(next, null);
      expect(await second, isNull);
      expect(window.launches, 1);
    },
  );

  test(
    'a crashed form fails the request and a later open starts a fresh process',
    () async {
      await service.warmUp();
      final first = service.show(request);
      final failed = expectLater(first, throwsStateError);
      await window.next();
      await window.close();
      await failed;
      final next = service.show(request);
      // Wait until the launch callback replaces the disconnected fake socket.
      while (window.launches < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      window.reply(await window.next(), null);
      expect(await next, isNull);
      expect(window.launches, 2);
    },
  );

  test('rejects relative destinations', () async {
    await service.warmUp();
    final result = service.show(request);
    final failed = expectLater(result, throwsFormatException);
    window.reply(await window.next(), {
      'destination': 'relative',
      'startImmediately': true,
    });
    await failed;
  });

  test('each queued form reads its parent at the time it opens', () async {
    await service.dispose();
    var parent = 101;
    var captures = 0;
    service = TorrentOptionsWindowService.forTesting(
      launch: window.launch,
      captureAnchor: () async {
        captures++;
        return TorrentOptionsWindowAnchor(windowId: parent);
      },
    );
    await service.warmUp();
    expect(captures, 0);
    final first = service.show(request);
    final second = service.show(request);
    final message = await window.next();
    expect(message['anchor'], {'windowId': 101});
    expect(captures, 1);
    parent = 202;
    window.reply(message, null);
    await first;
    final next = await window.next();
    expect(next['anchor'], {'windowId': 202});
    expect(captures, 2);
    window.reply(next, null);
    await second;
    expect(window.launches, 1);
  });

  test('an active torrent cannot change its locked destination', () async {
    await service.warmUp();
    final result = service.show(
      TorrentDownloadRequest(
        name: 'Active',
        initialDestination: destination,
        destinationLocked: true,
      ),
    );
    final failed = expectLater(result, throwsFormatException);
    window.reply(
      await window.next(),
      TorrentDownloadOptions('$destination-other', true).toJson(),
    );
    await failed;
  });

  test('startup failure completes instead of leaving a waiting form', () async {
    await service.dispose();
    service = TorrentOptionsWindowService.forTesting(
      launch:
          ({
            required executable,
            required arguments,
            required environment,
            required workingDirectory,
          }) async => throw const ProcessException('app', [], 'failed'),
    );
    await expectLater(service.show(request), throwsA(isA<ProcessException>()));
  });
}
