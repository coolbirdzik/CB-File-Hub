import 'dart:async';

import '../../ui/controllers/operation_progress_controller.dart';
import '../local_ai/local_model_downloads.dart';
import '../torrent/torrent_service.dart';
import 'desktop_windowing_service.dart';
import 'windows_engine_host.dart';

/// Busy engines can outlive their visible window. Once their last operation
/// finishes the host releases secondary engines; the primary remains the
/// process coordinator until the last user window closes. File operations and
/// model downloads also keep the process alive past the last window; aria2
/// ownership does not, since seeding never finishes.
abstract final class EngineWindowLifetime {
  static void bind({
    required OperationProgressController operations,
    required TorrentService torrents,
    required LocalModelDownloads downloads,
    required DesktopWindowingService windows,
  }) {
    if (!WindowsEngineHost.isAvailable) return;
    void syncOperations() => unawaited(
      WindowsEngineHost.retainWhileBusy(
        'operations',
        operations.runningCount > 0,
      ),
    );
    void syncTorrents() => unawaited(
      WindowsEngineHost.retainWhileBusy(
        'torrent',
        torrents.ownsEngine,
        keepsProcess: false,
      ),
    );
    void syncDownloads() => unawaited(
      WindowsEngineHost.retainWhileBusy(
        'model-download',
        downloads.downloads.any((d) => !d.failed),
      ),
    );
    operations.addListener(syncOperations);
    torrents.addListener(syncTorrents);
    downloads.addListener(syncDownloads);
    syncOperations();
    syncTorrents();
    syncDownloads();
    WindowsEngineHost.onCloseRequested = () async {
      await windows.prepareForEngineClose();
      await WindowsEngineHost.close();
    };
  }
}
