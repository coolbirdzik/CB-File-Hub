import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cb_file_manager/services/streaming/smb_http_proxy_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_smb_native/mobile_smb_native.dart';

class FakeSmb extends MobileSmbNativePlatform {
  final bytes = List<int>.generate(100, (i) => i);
  SmbConnectionConfig? config;
  String? requestedPath;
  int disconnects = 0;
  @override
  Future<bool> connect(SmbConnectionConfig value) async {
    config = value;
    return true;
  }

  @override
  Future<bool> isConnected() async => true;
  @override
  Future<bool> disconnect() async {
    disconnects++;
    return true;
  }

  @override
  Future<SmbFile?> getFileInfo(String path) async {
    requestedPath = path;
    return SmbFile(
      name: path,
      path: path,
      isDirectory: false,
      size: bytes.length,
    );
  }

  @override
  Stream<List<int>> seekFileStreamOptimized(
    String path,
    int offset, {
    int chunkSize = 1024 * 1024,
  }) async* {
    yield bytes.sublist(offset);
  }
}

void main() {
  test(
    'SMB HTTP ranges reuse one bounded native reader per response',
    () async {
      final original = MobileSmbNativePlatform.instance;
      final smb = _PlaybackSmb();
      MobileSmbNativePlatform.instance = smb;
      final proxy = SmbHttpProxyServer.instance;
      final url = await proxy.urlFor(
        'smb://DOMAIN%3Buser:pass@nas:1445/My%20Share/a%2520%23.mp4',
      );
      final client = HttpClient();
      addTearDown(() {
        client.close(force: true);
        proxy.release(url);
        MobileSmbNativePlatform.instance = original;
      });

      final head = await (await client.headUrl(url)).close();
      expect(head.statusCode, 200);
      expect(head.contentLength, smb.bytes.length);
      await head.drain<void>();
      expect(smb.readers.single.reads, isEmpty);
      await smb.readers.single.closed.future;

      const start = 191;
      const length = 2304 * 1024;
      final request = await client.getUrl(url);
      request.headers.set('Range', 'bytes=$start-${start + length - 1}');
      final response = await request.close();
      expect(response.statusCode, 206);
      expect(response.contentLength, length);
      final bytes = await response.fold<BytesBuilder>(
        BytesBuilder(copy: false),
        (all, chunk) => all..add(chunk),
      );
      expect(
        bytes.takeBytes(),
        Uint8List.sublistView(smb.bytes, start, start + length),
      );
      expect(smb.readers, hasLength(2));
      expect(smb.readers.last.reads, [
        (start, 256 * 1024),
        (start + 256 * 1024, 1024 * 1024),
        (start + 1280 * 1024, 1024 * 1024),
      ]);
      await smb.readers.last.closed.future;
      expect(proxy.bytesRead(url), length);
      expect(smb.path, 'a%20#.mp4');
      expect(smb.config!.shareName, 'My Share');
      expect(smb.config!.domain, 'DOMAIN');
      expect(smb.config!.port, 1445);

      final invalid = await client.getUrl(url);
      invalid.headers.set('Range', 'bytes=${smb.bytes.length}-');
      final rejected = await invalid.close();
      expect(rejected.statusCode, 416);
      await rejected.drain<void>();
      expect(smb.readers, hasLength(3));
      await smb.readers.last.closed.future;
      expect(smb.readers.last.reads, isEmpty);
    },
  );

  test(
    'SMB proxy preserves credentials and literal paths, serves ranges and expires URLs',
    () async {
      final original = MobileSmbNativePlatform.instance;
      final smb = FakeSmb();
      MobileSmbNativePlatform.instance = smb;
      final client = HttpClient();
      final proxy = SmbHttpProxyServer.instance;
      const source =
          'smb://DOMAIN%3Buser:p%40ss:a%23%25@nas:1445/share/a%2520%23.mp4';
      final url = await proxy.urlFor(source);
      final otherUrl = await proxy.urlFor(source);
      try {
        expect(url.host, '127.0.0.1');
        expect(url.toString(), isNot(contains('user')));
        expect(proxy.bytesRead(url), 0);
        var bytesRead = 0;
        for (final scenario in [
          (range: 'bytes=10-19', start: 10, end: 19),
          (range: 'bytes=-10', start: 90, end: 99),
          (range: 'bytes=0-', start: 0, end: 99),
        ]) {
          final request = await client.getUrl(url);
          request.headers.set('Range', scenario.range);
          final response = await request.close();
          expect(response.statusCode, 206);
          expect(
            response.headers.value('Content-Range'),
            'bytes ${scenario.start}-${scenario.end}/100',
          );
          final body = await response.fold<List<int>>(
            [],
            (all, part) => all..addAll(part),
          );
          expect(body, smb.bytes.sublist(scenario.start, scenario.end + 1));
          bytesRead += body.length;
          expect(proxy.bytesRead(url), bytesRead);
          expect(proxy.bytesRead(otherUrl), 0);
        }
        expect(smb.config!.domain, 'DOMAIN');
        expect(smb.config!.username, 'user');
        expect(smb.config!.password, 'p@ss:a#%');
        expect(smb.config!.port, 1445);
        expect(smb.requestedPath, 'a%20#.mp4');
        expect(smb.disconnects, 3);
        final invalid = await client.getUrl(url);
        invalid.headers.set('Range', 'bytes=100-');
        final rejected = await invalid.close();
        expect(rejected.statusCode, 416);
        await rejected.drain<void>();
        final metadata = await (await client.headUrl(url)).close();
        expect(metadata.statusCode, 200);
        await metadata.drain<void>();
        expect(proxy.bytesRead(url), bytesRead);
        proxy.release(url);
        expect(proxy.bytesRead(url), isNull);
        expect(proxy.bytesRead(otherUrl), 0);
        final expired = await (await client.getUrl(url)).close();
        expect(expired.statusCode, 404);
        await expired.drain<void>();
      } finally {
        proxy.release(otherUrl);
        proxy.release(url);
        client.close(force: true);
        MobileSmbNativePlatform.instance = original;
      }
    },
  );
}

class _PlaybackSmb extends MobileSmbNativePlatform {
  final bytes = Uint8List.fromList(
    List<int>.generate(3 * 1024 * 1024, (index) => index % 251),
  );
  final readers = <_PlaybackReader>[];
  SmbConnectionConfig? config;
  String? path;

  @override
  Future<SmbPlaybackReader> openPlaybackReader(
    SmbConnectionConfig config,
    String path,
  ) async {
    this.config = config;
    this.path = path;
    final reader = _PlaybackReader(bytes);
    readers.add(reader);
    return reader;
  }
}

class _PlaybackReader implements SmbPlaybackReader {
  _PlaybackReader(this.bytes);

  final Uint8List bytes;
  final reads = <(int, int)>[];
  final closed = Completer<void>();

  @override
  int get fileSize => bytes.length;

  @override
  Future<Uint8List> read(int offset, int length) async {
    expect(closed.isCompleted, isFalse);
    reads.add((offset, length));
    return Uint8List.sublistView(bytes, offset, offset + length);
  }

  @override
  Future<void> close() async {
    closed.complete();
  }
}
