import 'dart:io';

import 'package:cb_file_manager/services/windows_shell_properties.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final skip = Platform.isWindows ? false : 'Windows Shell only';

  test('reads Explorer properties of real files in one batch', () async {
    final dir = await Directory.systemTemp.createTemp('cb_shell_props_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, 'note.txt'))..writeAsStringSync('hi');
    // A Windows binary always carries a version resource.
    final exe = p.join(
      Platform.environment['SystemRoot'] ?? r'C:\Windows',
      'explorer.exe',
    );
    final properties = WindowsShellProperties.instance;

    final results = await Future.wait([
      properties.get(file.path, 'owner'),
      properties.get(file.path, 'album'),
      properties.get(exe, 'fileVersion'),
      properties.get(p.join(dir.path, 'missing.txt'), 'owner'),
    ]);

    expect(results[0], isNotEmpty, reason: 'every NTFS file has an owner');
    expect(results[1], isEmpty, reason: 'a text file has no album');
    expect(results[2], matches(RegExp(r'^\d+(\.\d+)*')));
    expect(results[3], isEmpty);
    expect(await properties.getSortKey(file.path, 'duration'), isEmpty);
    expect(await properties.getSortKey(file.path, 'pageCount'), isEmpty);
    // Cached afterwards.
    expect(properties.peek(file.path, 'owner'), results[0]);
  }, skip: skip);

  test('reads image and audio properties of Windows sample media', () async {
    final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final image = p.join(root, 'Web', 'Wallpaper', 'Windows', 'img0.jpg');
    final sound = p.join(root, 'Media', 'Alarm01.wav');
    if (!File(image).existsSync() || !File(sound).existsSync()) {
      markTestSkipped('Windows sample media is not installed');
      return;
    }
    final properties = WindowsShellProperties.instance;
    expect(
      await properties.get(image, 'dimensions'),
      matches(RegExp(r'^\d+ x \d+$')),
    );
    expect(await properties.get(sound, 'duration'), isNotEmpty);
    expect(await properties.get(sound, 'bitRate'), isNotEmpty);
    expect(
      await properties.getSortKey(image, 'dimensions'),
      matches(RegExp(r'^\d+,\d+$')),
    );
    expect(
      int.parse(await properties.getSortKey(sound, 'duration')),
      greaterThan(0),
    );
    expect(
      int.parse(await properties.getSortKey(sound, 'bitRate')),
      greaterThan(0),
    );
  }, skip: skip);
}
