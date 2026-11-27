/// What a leftover scan is doing right now, for the status line.
enum AppLeftoverScanStage {
  /// Loading the installed-app inventory (registry / package managers).
  readingApps,

  /// Listing the app-data and program base folders.
  listingFolders,

  /// Looking for runnable files inside each proposed leftover folder.
  checkingCandidates,

  /// Deep scan: looking for command-line tools in the PATH folders.
  checkingPath,

  /// Deep scan: walking one fixed drive for portable apps.
  searchingDrive,

  /// Measuring size and last activity of each remaining folder.
  measuring,
}

/// One progress tick. Sent across isolates, so it holds plain values only.
class AppLeftoverScanProgress {
  final AppLeftoverScanStage stage;

  /// The folder being read.
  final String path;

  /// The drive being searched ([AppLeftoverScanStage.searchingDrive]); empty
  /// otherwise.
  final String root;

  /// Items finished in this stage, and how many there are. For
  /// [AppLeftoverScanStage.searchingDrive] these count drives.
  final int done;
  final int total;

  /// Entries enumerated so far on the current drive.
  final int visited;

  const AppLeftoverScanProgress({
    required this.stage,
    this.path = '',
    this.root = '',
    this.done = 0,
    this.total = 0,
    this.visited = 0,
  });
}

/// Passes on a tick at once when the stage or drive changes, otherwise at
/// most once per [interval]. A drive walk visits millions of entries; sending
/// one message per folder would flood the isolate port and the UI.
class AppLeftoverProgressThrottle {
  final void Function(AppLeftoverScanProgress progress) _send;
  final Duration interval;
  final Stopwatch _clock = Stopwatch()..start();
  AppLeftoverScanStage? _stage;
  String? _root;

  AppLeftoverProgressThrottle(
    this._send, {
    this.interval = const Duration(milliseconds: 120),
  });

  void call(AppLeftoverScanProgress progress) {
    if (progress.stage == _stage &&
        progress.root == _root &&
        _clock.elapsed < interval) {
      return;
    }
    _stage = progress.stage;
    _root = progress.root;
    _clock.reset();
    _send(progress);
  }
}
