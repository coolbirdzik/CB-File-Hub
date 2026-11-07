import 'package:cb_file_manager/services/disk_cleaner/app_storage/app_space_analyzer.dart';
import 'package:cb_file_manager/services/disk_cleaner/editor_storage/editor_storage_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  for (final os in ['macos', 'linux', 'windows']) {
    test(
      '$os layout retains POSIX filesystem syntax for a slash-rooted home',
      () {
        const home = '/tmp/cb-home';
        final app = AppSpaceEnvironment(operatingSystem: os, home: home);
        final editor = EditorStorageEnvironment(
          operatingSystem: os,
          home: home,
        );
        for (final context in [app.path, editor.path]) {
          expect(
            context.join(home, 'Library', 'Application Support', 'Code'),
            '/tmp/cb-home/Library/Application Support/Code',
          );
          expect(
            context.basename('/tmp/cb-home/Library/Containers/com.notes.Notes'),
            'com.notes.Notes',
          );
        }
      },
    );
  }

  test(
    'macOS editor roots resolve correctly on a POSIX filesystem on any host',
    () {
      const app = AppSpaceEnvironment(
        operatingSystem: 'macos',
        home: '/Users/tester',
      );
      expect(
        app.editor.dataRoot(EditorProduct.all.first),
        '/Users/tester/Library/Application Support/Code',
      );
      expect(
        app.editor.extensionsRoot(EditorProduct.all.first),
        '/Users/tester/.vscode/extensions',
      );
    },
  );

  for (final home in [
    r'C:\Users\tester',
    'C:/Users/tester',
    r'\\server\profiles\tester',
    '//server/profiles/tester',
  ]) {
    test('Windows home $home keeps its drive or UNC root', () {
      final app = AppSpaceEnvironment(operatingSystem: 'macos', home: home);
      final editor = EditorStorageEnvironment(
        operatingSystem: 'macos',
        home: home,
      );
      for (final context in [app.path, editor.path]) {
        expect(context.style, p.Style.windows);
        final data = context.join(home, 'Library', 'Application Support');
        expect(context.rootPrefix(data), p.windows.rootPrefix(home));
        expect(context.basename(data), 'Application Support');
      }
    });
  }
}
