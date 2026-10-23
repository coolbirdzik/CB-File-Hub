import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive_io.dart';
import 'package:cb_file_manager/helpers/files/recycle_bin_reader.dart';
import 'package:cb_file_manager/helpers/media/image_transcoder.dart';
import 'package:cb_native/cb_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  final skip = CbNative.isAvailable ? null : 'Rust library not built';
  late Directory root;
  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('cb_native_extra_'),
  );
  tearDown(() => root.delete(recursive: true));

  test('header dimensions match Flutter including EXIF axis swaps', () async {
    final image = img.Image(width: 11, height: 7);
    final jpeg = img.encodeJpg(image);
    final exif = ByteData(32);
    exif.buffer.asUint8List().setAll(0, [69, 120, 105, 102, 0, 0, 73, 73]);
    exif.setUint16(8, 42, Endian.little);
    exif.setUint32(10, 8, Endian.little);
    exif.setUint16(14, 1, Endian.little);
    exif.setUint16(16, 0x112, Endian.little);
    exif.setUint16(18, 3, Endian.little);
    exif.setUint32(20, 1, Endian.little);
    for (final orientation in [1, 5, 6, 7, 8]) {
      exif.setUint16(24, orientation, Endian.little);
      final bytes = Uint8List.fromList([
        0xff,
        0xd8,
        0xff,
        0xe1,
        0,
        34,
        ...exif.buffer.asUint8List(),
        ...jpeg.skip(2),
      ]);
      final file = await File(
        p.join(root.path, 'oriented.jpg'),
      ).writeAsBytes(bytes);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(await NativeImage.dimensions(file.path), (
        frame.image.width,
        frame.image.height,
      ), reason: 'orientation $orientation');
      frame.image.dispose();
      codec.dispose();
    }
    final bad = await File(p.join(root.path, 'bad.png')).writeAsString('bad');
    expect(await NativeImage.dimensions(bad.path), isNull);
  }, skip: skip);

  test(
    'full resolution JPEG conversion and fallback preserve dimensions',
    () async {
      final source = img.Image(width: 137, height: 91);
      img.fill(source, color: img.ColorRgb8(30, 80, 150));
      final bytes = Uint8List.fromList(img.encodePng(source));
      final native = await NativeImage.transcode(bytes);
      expect(native, isNotNull);
      for (final result in [
        native!,
        (await transcodeJpeg(bytes, useNative: false))!,
      ]) {
        final decoded = img.decodeJpg(result)!;
        expect((decoded.width, decoded.height), (137, 91));
        expect(decoded.getPixel(50, 50).r, closeTo(30, 5));
      }
      expect(await transcodeJpeg(Uint8List.fromList([1, 2, 3])), isNull);
    },
    skip: skip,
  );

  test(
    'batch existence matches Dart for files, folders, duplicates and missing paths',
    () async {
      final file = await File(
        p.join(root.path, 'Tiếng Việt.txt'),
      ).writeAsString('x');
      final paths = [file.path, root.path, '${file.path}.missing', file.path];
      expect(
        await NativeFs.filesExist(paths),
        await Future.wait(paths.map((s) => File(s).exists())),
      );
      expect(await NativeFs.filesExist([]), isEmpty);
    },
    skip: skip,
  );

  test(
    'JPEG transcode flattens transparent pixels onto white like Dart',
    () async {
      for (final alpha in [0, 64, 128, 255]) {
        final image = img.Image(width: 32, height: 32, numChannels: 4);
        img.fill(image, color: img.ColorRgba8(30, 80, 150, alpha));
        final bytes = Uint8List.fromList(img.encodePng(image));
        final native = img.decodeJpg((await NativeImage.transcode(bytes))!)!;
        final dart = img.decodeJpg(
          (await transcodeJpeg(bytes, useNative: false))!,
        )!;
        final a = native.getPixel(16, 16), b = dart.getPixel(16, 16);
        expect(a.r, closeTo(b.r, 4));
        expect(a.g, closeTo(b.g, 4));
        expect(a.b, closeTo(b.b, 4));
      }
    },
    skip: skip,
  );

  test(
    'native ZIP creation interoperates with Dart and reads only requested members',
    () async {
      final a = await File(
        p.join(root.path, 'settings.json'),
      ).writeAsString('{"theme":"dark"}');
      final b = await File(
        p.join(root.path, 'tags.json'),
      ).writeAsString('tag' * 100000);
      final zip = p.join(root.path, 'backup.zip');
      expect(
        await NativeArchive.createZip(zip, {
          a.path: 'settings.json',
          b.path: 'tags.json',
        }),
        isTrue,
      );
      final dart = ZipDecoder().decodeBytes(
        await File(zip).readAsBytes(),
        verify: true,
      );
      expect(dart.findFile('tags.json')!.content, await b.readAsBytes());
      expect(
        (await NativeArchive.readZipEntry(zip, 'settings.json'))!.bytes,
        await a.readAsBytes(),
      );
      expect(
        (await NativeArchive.readZipEntry(zip, 'absent.json'))!.bytes,
        isNull,
      );
      final dartZip = p.join(root.path, 'dart.zip');
      final encoder = ZipFileEncoder()..create(dartZip);
      encoder.addFileSync(a, 'settings.json');
      encoder.closeSync();
      expect(
        (await NativeArchive.readZipEntry(dartZip, 'settings.json'))!.bytes,
        await a.readAsBytes(),
      );
      await File(zip).writeAsString('invalid');
      expect(
        () => NativeArchive.readZipEntry(zip, 'settings.json'),
        throwsA(isA<NativeJobException>()),
      );
    },
    skip: skip,
  );

  test(
    'streamed native Recycle Bin metadata matches Dart and excludes orphans',
    () async {
      final sid = await Directory(p.join(root.path, 'S-1-test')).create();
      for (final version in [1, 2]) {
        for (final folder in [false, true]) {
          final suffix = '$version-$folder';
          final original = 'C:\\Ảnh\\$suffix.png\u0000';
          final data = ByteData(version == 1 ? 544 : 28 + original.length * 2)
            ..setInt64(0, version, Endian.little)
            ..setInt64(8, 1234, Endian.little)
            ..setInt64(
              16,
              version == 2 && folder ? -133000000000000000 : 133000000000000000,
              Endian.little,
            );
          final start = version == 1 ? 24 : 28;
          if (version == 2) data.setInt32(24, original.length, Endian.little);
          for (var i = 0; i < original.length; i++) {
            data.setUint16(
              start + i * 2,
              original.codeUnitAt(i),
              Endian.little,
            );
          }
          await File(
            p.join(sid.path, '\$I$suffix'),
          ).writeAsBytes(data.buffer.asUint8List());
          final payload = p.join(sid.path, '\$R$suffix');
          if (folder) {
            await Directory(payload).create();
          } else {
            await File(payload).writeAsString('x');
          }
        }
      }
      await File(
        p.join(sid.path, r'$Iorphan'),
      ).writeAsBytes(List.filled(544, 0));
      final entries = <NativeRecycleEntry>[];
      expect(
        await NativeFs.recycleBin(
          roots: [root.path],
          onEntries: entries.addAll,
        ),
        isTrue,
      );
      expect(entries.length, 4);
      for (final entry in entries) {
        final metadata = File(
          p.join(sid.path, p.basename(entry.path).replaceFirst(r'$R', r'$I')),
        );
        final dart = readRecycleBinMetadata(metadata)!;
        expect(entry.path, dart.recycleBinPath);
        expect(entry.originalPath, dart.originalPath);
        expect(entry.size, dart.size);
        expect(entry.deletedMs, dart.trashedDate.millisecondsSinceEpoch);
        expect(entry.isDirectory, dart.isFolder);
      }
    },
    skip: skip,
  );
}
