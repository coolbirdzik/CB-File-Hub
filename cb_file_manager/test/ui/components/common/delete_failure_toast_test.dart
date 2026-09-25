import 'dart:io';

import 'package:cb_file_manager/ui/components/common/delete_failure_toast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only access-denied failures are offered an elevated retry', () {
    const denied = r'E:\locked\a.mp4';
    const inUse = r'E:\busy\b.mp4';
    const unknown = r'E:\other\c.mp4';

    final retryPaths = DeleteFailureToast.accessDeniedPaths(
      const [denied, inUse, unknown],
      {
        denied: const FileSystemException(
          'Deletion failed',
          denied,
          OSError('Access is denied', 5),
        ),
        inUse: const FileSystemException(
          'Deletion failed',
          inUse,
          OSError('The process cannot access the file', 32),
        ),
      },
    );

    expect(retryPaths, [denied]);
  });
}
