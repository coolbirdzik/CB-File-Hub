import 'dart:async';
import 'dart:isolate';
import 'package:cb_file_manager/helpers/core/filesystem_utils.dart';

// Isolate entry point
void albumIsolateEntry(SendPort sendPort) async {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  await for (final message in receivePort) {
    if (message is Map<String, dynamic>) {
      final directoryPath = message['directoryPath'] as String;
      final replyPort = message['replyPort'] as SendPort;

      try {
        final imageFiles = await getAllImages(directoryPath, recursive: true);
        final totalFiles = imageFiles.length;
        int processedFiles = 0;

        replyPort.send({
          'status': 'scanning',
          'current': 0,
          'total': totalFiles,
        });

        for (final _ in imageFiles) {
          // In a real isolate, you'd need a mechanism to access the database.
          // For this example, we simulate the work and send progress.
          processedFiles++;

          if (processedFiles % 50 == 0 || processedFiles == totalFiles) {
            replyPort.send({
              'status': 'processing',
              'current': processedFiles,
              'total': totalFiles,
            });
          }
          // Simulate DB work
          await Future.delayed(const Duration(milliseconds: 2));
        }

        replyPort.send({
          'status': 'completed',
          'current': totalFiles,
          'total': totalFiles,
        });
      } catch (e) {
        replyPort.send({'status': 'error', 'error': e.toString()});
      }
    }
  }
}
