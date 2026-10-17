import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/services/torrent/aria2_engine.dart';
import 'package:cb_file_manager/services/torrent/torrent_metainfo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'torrent_fixtures.dart';

class _Headers extends Fake implements HttpHeaders {
  @override
  ContentType? contentType;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  final Object payload;
  _Response(this.payload);
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode(jsonEncode(payload))).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request extends Fake implements HttpClientRequest {
  @override
  final HttpHeaders headers = _Headers();
  @override
  int contentLength = -1;
  final bytes = <int>[];
  Object response = {'jsonrpc': '2.0', 'id': 'cb', 'result': 'OK'};
  @override
  void add(List<int> data) {
    bytes.addAll(data);
  }

  @override
  Future<HttpClientResponse> close() async => _Response(response);
}

class _Client extends Fake implements HttpClient {
  final request = _Request();
  Uri? uri;
  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    uri = url;
    return request;
  }

  @override
  void close({bool force = false}) {}
}

class _Engine extends Aria2Engine {
  _Engine(_Client client)
    : super.forRpcTesting(
        port: 43210,
        secret: 'test-secret',
        httpClient: client,
      );
  @override
  bool get running => true;
}

void main() {
  test(
    'RPC uses UTF-8 byte length rather than chunked encoding or string length',
    () async {
      final client = _Client();
      final engine = _Engine(client);
      final result = await engine.call('changeOption', [
        'gid',
        {'dir': 'D:/Tải về'},
      ]);
      final raw = utf8.decode(client.request.bytes);
      final body = jsonDecode(raw) as Map<String, dynamic>;
      expect(client.uri.toString(), 'http://127.0.0.1:43210/jsonrpc');
      expect(client.request.contentLength, client.request.bytes.length);
      expect(client.request.contentLength, greaterThan(raw.length));
      expect(client.request.headers.contentType, ContentType.json);
      expect(body['method'], 'aria2.changeOption');
      expect(body['params'], [
        'token:test-secret',
        'gid',
        {'dir': 'D:/Tải về'},
      ]);
      expect(result, 'OK');
    },
  );

  test(
    'saved magnet metainfo accepts a payload GID while checking the actual info hash',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'cb-magnet-metainfo-',
      );
      try {
        final bytes = torrentBytes();
        final file = await File(
          '${directory.path}/metadata.torrent',
        ).writeAsBytes(bytes);
        final client = _Client();
        final engine = _Engine(client);
        await engine.add(
          file.path,
          directory.path,
          '1234567890abcdef',
          expectedHash: TorrentMetainfo.parse(bytes).hash,
        );
        final body = jsonDecode(utf8.decode(client.request.bytes)) as Map;
        expect(body['method'], 'aria2.addTorrent');
        expect((body['params'] as List)[3]['gid'], '1234567890abcdef');
        await expectLater(
          engine.add(
            file.path,
            directory.path,
            '1234567890abcdef',
            expectedHash: 'f' * 40,
          ),
          throwsFormatException,
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('RPC preserves engine error codes for missing-task recovery', () async {
    final client = _Client();
    client.request.response = {
      'jsonrpc': '2.0',
      'id': 'cb',
      'error': {'code': 1, 'message': 'GID#123 is not found'},
    };
    await expectLater(
      _Engine(client).call('tellStatus', ['123']),
      throwsA(
        isA<Aria2RpcException>()
            .having((e) => e.code, 'code', 1)
            .having((e) => e.message, 'message', contains('not found')),
      ),
    );
  });

  test(
    'magnet RPC preserves trackers, destination, pause and payload following',
    () async {
      final client = _Client();
      const magnet =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&tr=https%3A%2F%2Ftracker.example';
      await _Engine(
        client,
      ).addMagnet(magnet, r'D:\Tải về', 'gid', paused: true);
      final body = jsonDecode(utf8.decode(client.request.bytes)) as Map;
      expect(body['method'], 'aria2.addUri');
      final params = body['params'] as List;
      expect(params[1], [magnet]);
      expect(params[2], {
        'dir': r'D:\Tải về',
        'gid': 'gid',
        'pause': 'true',
        'seed-time': '0',
        'bt-metadata-only': 'false',
        'bt-save-metadata': 'true',
        'check-integrity': 'true',
      });
    },
  );
}
