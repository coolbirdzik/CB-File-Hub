import 'dart:io';
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
    'SMB proxy preserves credentials and literal paths, serves ranges and expires URLs',
    () async {
      final original = MobileSmbNativePlatform.instance;
      final smb = FakeSmb();
      MobileSmbNativePlatform.instance = smb;
      final client = HttpClient();
      final proxy = SmbHttpProxyServer.instance;
      final url = await proxy.urlFor(
        'smb://DOMAIN%3Buser:p%40ss:a%23%25@nas:1445/share/a%2520%23.mp4',
      );
      try {
        expect(url.host, '127.0.0.1');
        expect(url.toString(), isNot(contains('user')));
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
        proxy.release(url);
        final expired = await (await client.getUrl(url)).close();
        expect(expired.statusCode, 404);
        await expired.drain<void>();
      } finally {
        proxy.release(url);
        client.close(force: true);
        MobileSmbNativePlatform.instance = original;
      }
    },
  );
}
