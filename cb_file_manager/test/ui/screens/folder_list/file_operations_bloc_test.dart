import 'dart:io';

import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_operations_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('operation state clears an old error before an elevated retry', () {
    const failedPath = r'E:\approved\one';
    const state = FileOperationsState(
      error: 'Access denied',
      retryableElevatedDeletePaths: [failedPath],
    );

    final retrying = state.copyWith(
      error: null,
      retryableElevatedDeletePaths: const <String>[],
    );

    expect(retrying.error, isNull);
    expect(retrying.retryableElevatedDeletePaths, isEmpty);
  });

  test('formats access denied deletion failures with path and guidance', () {
    const failedPath = r'E:\reco\RecoE\V';
    final message = FileOperationsBloc.formatDeleteFailure(
      failedPaths: const [failedPath],
      errorsByPath: {
        failedPath: const FileSystemException(
          'Deletion failed',
          failedPath,
          OSError('Access is denied', 5),
        ),
      },
    );

    expect(message, contains(failedPath));
    expect(message, contains('Access denied'));
    expect(message, contains('administrator'));
  });

  test('formats generic deletion failures without exposing stack traces', () {
    const failedPath = r'E:\data\locked.txt';
    final message = FileOperationsBloc.formatDeleteFailure(
      failedPaths: const [failedPath],
      errorsByPath: {
        failedPath: const FileSystemException(
          'Deletion failed',
          failedPath,
          OSError('The process cannot access the file', 32),
        ),
      },
    );

    expect(
      message,
      'Could not delete "$failedPath": The process cannot access the file.',
    );
    expect(message, isNot(contains('dart:io')));
  });

  test('elevated retry cannot broaden the approved failed path set', () {
    final retained = FileOperationsBloc.retainApprovedRetryPaths(
      approvedPaths: const [r'E:\approved\one', r'E:\approved\two'],
      requestedPaths: const [
        r'E:\approved\two',
        r'E:\not-approved\three',
        r'E:\approved\two',
      ],
    );

    expect(retained, const [r'E:\approved\two']);
  });
}
