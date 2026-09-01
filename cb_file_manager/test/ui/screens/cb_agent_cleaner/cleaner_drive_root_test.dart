import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cb_agent_cleaner_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonicalizes drive-root picker variants', () {
    for (final input in <String>[
      'C:',
      r'C:\',
      'c:/',
      r' c:\ ',
      ' c:/ ',
      r'c:/\\',
    ]) {
      expect(
        normalizeCleanerDriveRoot(input),
        r'C:\',
        reason: 'Expected $input to normalize to the canonical drive root',
      );
    }
  });

  test('drive-root normalization is idempotent', () {
    for (final input in <String>['C:', r' c:/ ', r'D:\']) {
      final normalized = normalizeCleanerDriveRoot(input);

      expect(normalizeCleanerDriveRoot(normalized), normalized);
    }
  });

  test('preserves non-root paths while normalizing separators and whitespace',
      () {
    expect(
      normalizeCleanerDriveRoot(r' C:\Users\Cleaner '),
      r'C:\Users\Cleaner',
    );
    expect(
      normalizeCleanerDriveRoot('c:/Users/Cleaner'),
      r'c:\Users\Cleaner',
    );
  });
}
