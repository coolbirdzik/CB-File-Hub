import 'dart:io';

import 'package:cb_file_manager/services/ai/tool_executor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// A model that copies a long file name slightly wrong must get the real
/// name back, and nothing may be deleted on a guess.
void main() {
  late Directory dir;
  const realName = '049AD5AE4C9996E008D7877DB31F2C665227DE8B.pptd';

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cb_delete_near_miss_');
    await File(p.join(dir.path, realName)).writeAsString('cache');
  });

  tearDown(() => dir.delete(recursive: true));

  test('a near-miss path names the real file and deletes nothing', () async {
    final typo = p.join(
      dir.path,
      '049AD5AE4C9996E08D7877DB31F2C665227DE8B.pptd',
    );
    final result = await ToolExecutor(
      ownerTabId: 'tab-a',
    ).execute(ToolCall(name: 'delete_file', arguments: {'path': typo}));

    expect(result.success, isFalse);
    expect(
      result.output,
      contains('Did you mean ${p.join(dir.path, realName)}'),
    );
    expect(File(p.join(dir.path, realName)).existsSync(), isTrue);
  });
}
