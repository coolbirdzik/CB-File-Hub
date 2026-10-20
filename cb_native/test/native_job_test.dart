import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:cb_native/cb_native.dart';
import 'package:test/test.dart';

/// End-to-end checks of the job-based APIs through FFI: wire formats on both
/// sides agree and results come back through the port notification.
void main() {
  final skip = CbNative.isAvailable ? null : 'Rust library not built';
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('cb_native_job_');
    await Directory('${root.path}/a/b').create(recursive: true);
    await Directory('${root.path}/.hidden').create();
    await File('${root.path}/one.jpg').writeAsBytes(List.filled(3, 0));
    await File('${root.path}/a/two.JPG').writeAsBytes(List.filled(5, 0));
    await File('${root.path}/a/b/three.png').writeAsBytes(List.filled(7, 0));
    await File('${root.path}/a/b/note.txt').writeAsBytes(List.filled(11, 0));
    await File(
      '${root.path}/.hidden/four.jpg',
    ).writeAsBytes(List.filled(13, 0));
  });

  tearDown(() => root.delete(recursive: true));

  String name(String path) => path.split(RegExp(r'[\\/]')).last;

  test('directorySize sums files and folders', () async {
    final result = await NativeFs.directorySize(
      files: ['${root.path}/one.jpg'],
      directories: ['${root.path}/a', '${root.path}/missing'],
    );
    expect(result!.bytes, 3 + 5 + 7 + 11);
    expect(result.files, 4);
    expect(result.unreadable, 1);
  }, skip: skip);

  test('listDirectory sorts like the folder browser', () async {
    final listing = await NativeFs.listDirectory(
      root.path,
      sort: NativeListSort.nameAsc,
    );
    expect(listing!.folders.map((e) => name(e.path)), ['.hidden', 'a']);
    expect(listing.files.map((e) => name(e.path)), ['one.jpg']);
    expect(await NativeFs.listDirectory('${root.path}/missing'), isNull);
  }, skip: skip);

  test('walk filters by extension and regex', () async {
    final entries = await NativeFs.walk(
      roots: [root.path],
      skipDotNames: true,
      stats: true,
      extensionMode: NativeExtensionMode.lastDot,
      extensions: ['.jpg', '.png'],
      excludeNameRegexes: ['^three'],
    );
    final byName = {for (final e in entries!) name(e.path): e.size};
    expect(byName, {'one.jpg': 3, 'two.JPG': 5, 'four.jpg': 13});
    expect(
      await NativeFs.walk(roots: [root.path], excludeNameRegexes: ['(']),
      isNull,
    );
  }, skip: skip);

  test('junkScan reports rule matches', () async {
    final key = Platform.isWindows
        ? root.path.replaceAll('/', r'\').toLowerCase()
        : root.path;
    final result = await NativeFs.junkScan(
      scanPath: root.path,
      recursive: true,
      lowerCaseKeys: Platform.isWindows,
      rules: [
        NativeJunkRule(
          index: 0,
          baseKey: key,
          recursive: true,
          includeGlobs: const ['*.txt'],
        ),
      ],
    );
    expect(result!.hits.map((h) => name(h.path)), ['note.txt']);
    expect(result.hits.single.ruleIndices, [0]);
    expect(result.error, isNull);
  }, skip: skip);

  test('sha256File matches a known digest', () async {
    final file = File('${root.path}/abc.txt')..writeAsStringSync('abc');
    final digest = await NativeHash.sha256File(file.path);
    final hex = digest!.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    expect(
      hex,
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(
      () => NativeHash.sha256File('${root.path}/missing'),
      throwsA(isA<NativeJobException>()),
    );
  }, skip: skip);

  test('archive list and extract round-trip a zip', () async {
    final zipPath = '${root.path}/sample.zip';
    final encoder = ZipFileEncoder()..create(zipPath);
    encoder.addFileSync(File('${root.path}/a/b/note.txt'), 'docs/note.txt');
    encoder.closeSync();

    final entries = await NativeArchive.list(zipPath, NativeArchiveFormat.zip);
    expect(entries!.map((e) => e.name), contains('docs/note.txt'));

    final dest = '${root.path}/out';
    final progress = <int>[];
    expect(
      await NativeArchive.extract(
        path: zipPath,
        format: NativeArchiveFormat.zip,
        destination: dest,
        onProgress: (done, _) => progress.add(done),
      ),
      isTrue,
    );
    expect(File('$dest/docs/note.txt').lengthSync(), 11);
  }, skip: skip);

  test('thumbnail, encode and inpaint', () async {
    const w = 40, h = 30;
    final rgba = Uint8List(w * h * 4);
    for (var i = 0; i < w * h; i++) {
      rgba.setAll(i * 4, [i % 256, 120, 200, 255]);
    }
    final png = await NativeImage.encode(rgba, w, h, NativeImageFormat.png);
    expect(png, isNotNull);

    final thumb = await NativeImage.thumbnail(
      bytes: png,
      width: 20,
      height: 20,
      fit: NativeThumbnailFit.fit,
      filter: NativeResizeFilter.average,
      enhance: true,
    );
    expect((thumb!.width, thumb.height), (20, 15));
    expect(
      await NativeImage.thumbnail(bytes: Uint8List(10), width: 8, height: 8),
      isNull,
    );

    final mask = Uint8List(w * h)..[15 * w + 20] = 1;
    final filled = await NativeImage.inpaint(rgba, mask, w, h);
    expect(filled!.length, rgba.length);
  }, skip: skip);
}
