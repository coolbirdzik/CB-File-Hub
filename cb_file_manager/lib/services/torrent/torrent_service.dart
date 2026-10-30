import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cb_file_manager/helpers/core/file_hash.dart';

import '../../models/database/sqlite_database_provider.dart';
import '../drive/drive_info.dart';
import '../drive/drive_inventory_service.dart';
import 'aria2_engine.dart';
import 'torrent_entry.dart';
import 'torrent_metainfo.dart';
import 'torrent_repository.dart';
import 'torrent_preferences.dart';
import 'magnet_link.dart';
import 'torrent_import_confirmation.dart';
import 'torrent_launch_request.dart';
import 'torrent_source_discovery.dart';
import 'qbittorrent_backup_importer.dart';
import 'qbittorrent_resume.dart';

typedef _ScanSource = ({
  String path,
  String archive,
  int modified,
  int size,
  int version,
});

Future<Uint8List> _readTorrentBytes(String path) async {
  final handle = await File(path).open();
  try {
    if (await handle.length() > 16 * 1024 * 1024) {
      throw const FormatException('Torrent exceeds 16 MiB');
    }
    final bytes = await handle.read(16 * 1024 * 1024 + 1);
    if (bytes.length > 16 * 1024 * 1024) {
      throw const FormatException('Torrent exceeds 16 MiB');
    }
    return Uint8List.fromList(bytes);
  } finally {
    await handle.close();
  }
}

Future<TorrentMetainfo> _readTorrent(String path) async =>
    TorrentMetainfo.parseAsync(await _readTorrentBytes(path));

Future<void> _writeQbittorrentBackup(String path, List<int> bytes) async {
  final archive = File(path);
  await archive.parent.create(recursive: true);
  final temporary = File('$path.${DateTime.now().microsecondsSinceEpoch}.tmp');
  try {
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}

class TorrentService extends ChangeNotifier {
  static Future<List<String>> _noDiscoveredSources() async => [];
  static const _idleNetwork = <String, Object?>{
    'download_speed': 0,
    'upload_speed': 0,
    'seeders': null,
    'connections': null,
  };
  static final instance = TorrentService._();
  TorrentService._() : _engine = Aria2Engine(), _sourceDiscovery = null;

  @visibleForTesting
  TorrentService.forTesting({
    required this.repository,
    required SharedPreferences preferences,
    required String stateDirectory,
    Aria2Engine? engine,
    this._sourceDiscovery = _noDiscoveredSources,
  }) : _prefs = preferences,
       _stateDirectory = p.normalize(stateDirectory),
       _initialized = true,
       _engine = engine ?? Aria2Engine();

  late TorrentRepository repository;
  late SharedPreferences _prefs;
  late String _stateDirectory;
  final Aria2Engine _engine;
  // Older singleton instances survive hot reload with this new field unset.
  // Resolve the production default at call time instead of calling a null slot.
  final Future<List<String>> Function()? _sourceDiscovery;
  Future<void>? _initializing;
  bool _initialized = false;
  int? _importSchemaVersion;
  bool _syncing = false;
  Future<void>? _importRefresh;
  Completer<void>? _scanDone;
  bool _cancelScan = false;
  String? _currentScanLog;
  final Set<String> _actions = {};
  Timer? _pollTimer;
  Timer? _scanTimer;
  TorrentScanProgress scan = const TorrentScanProgress();
  String? lastError;
  Future<void> _backgroundImports = Future<void>.value();
  bool get ownsEngine => _engine.running;

  String? get libraryDirectory => _prefs.getString('torrent.libraryDirectory');
  String get storageMode => _prefs.getString('torrent.storageMode') ?? 'index';
  String? get executable => _prefs.getString('torrent.executable');
  bool get autoImport => _prefs.getBool('torrent.autoImport') ?? true;
  bool get showDownloadDialog =>
      _prefs.getBool('torrent.showDownloadDialog') ?? true;
  bool get receiveInBackground =>
      _prefs.getBool('torrent.receiveInBackground') ?? false;
  bool get startDownloadsImmediately =>
      _prefs.getBool('torrent.startImmediately') ?? true;
  String? get defaultDownloadDirectory =>
      _prefs.getString('torrent.lastDownloadDirectory');
  List<String> get scanRoots => _prefs.getStringList('torrent.scanRoots') ?? [];
  String get scanLogPath =>
      _currentScanLog ?? p.join(_stateDirectory, 'last-scan.log');
  String get qbittorrentImportDirectory =>
      _prefs.getString('torrent.qbittorrentImportDirectory') ??
      libraryDirectory ??
      p.join(_stateDirectory, 'qBittorrent-library');
  List<String> get qbittorrentSources =>
      _prefs.getStringList('torrent.qbittorrentSources') ?? const [];
  String get qbittorrentLogPath =>
      p.join(_stateDirectory, 'qbittorrent-import.log');

  Future<void> saveQbittorrentImportSettings(
    List<String> roots,
    String destination,
  ) async {
    await _prefs.setStringList('torrent.qbittorrentSources', roots);
    await _prefs.setString('torrent.qbittorrentImportDirectory', destination);
  }

  QbittorrentBackupImporter qbittorrentImporter({
    Future<bool> Function()? isRunning,
  }) => QbittorrentBackupImporter(
    save: _saveQbittorrentItem,
    verify: _verifyQbittorrentItem,
    verifyResumeCopies: (item, destination, digests) async {
      for (final file in item.files) {
        if (p.extension(file.path).toLowerCase() != '.fastresume') continue;
        final archive = File(item.resumeArchivePath(file.path, destination));
        if (!await archive.exists() ||
            await sha256OfFile(archive.path) != digests[file.path]) {
          throw StateError('qBittorrent resume copy differs from source');
        }
      }
    },
    logPath: qbittorrentLogPath,
    isRunning: isRunning,
  );

  Future<QbittorrentImportResult> importQbittorrent(
    QbittorrentImportPlan plan,
    String destination, {
    required bool removeSources,
    required bool confirmedRemoval,
    required bool Function() isCancelled,
    required void Function(int, int) onProgress,
  }) async {
    await initialize();
    if (_importRefresh != null) await _importRefresh;
    if (scan.running) throw StateError('A torrent import is already running');
    final completion = _scanDone = Completer<void>();
    _cancelScan = false;
    _currentScanLog = qbittorrentLogPath;
    scan = const TorrentScanProgress(running: true);
    notifyListeners();
    QbittorrentImportResult? result;
    try {
      await saveQbittorrentImportSettings(plan.roots, destination);
      return result = await qbittorrentImporter().run(
        plan,
        destination,
        removeSources: removeSources,
        confirmedRemoval: confirmedRemoval,
        isCancelled: () => _cancelScan || isCancelled(),
        onProgress: onProgress,
      );
    } finally {
      scan = TorrentScanProgress(
        visited: result?.processed ?? 0,
        imported: result?.stored ?? 0,
        failed: result?.failed ?? 0,
        cancelled: result?.cancelled ?? false,
        errors: result?.errors ?? const [],
      );
      completion.complete();
      notifyListeners();
    }
  }

  Future<void> _saveQbittorrentItem(
    QbittorrentBackupItem item,
    String destination,
  ) async {
    await initialize();
    // A running service can survive hot reload with the previous schema.
    if (_importSchemaVersion != TorrentRepository.schemaVersion) {
      await repository.initialize();
      _importSchemaVersion = TorrentRepository.schemaVersion;
    }
    final previous = await repository.get(item.hash);
    String? source;
    for (final candidate in [
      item.torrentPath,
      previous?.torrentPath,
      ...await repository.sources(item.hash),
    ].whereType<String>()) {
      if (candidate.isNotEmpty &&
          p.extension(candidate).toLowerCase() == '.torrent' &&
          await File(candidate).exists()) {
        source = candidate;
        break;
      }
    }
    // This entry point always copies, regardless of the normal import mode.
    // qBittorrent source removal is a separately confirmed, closed-app action.
    if (source != null) {
      await _importFile(
        source,
        mode: 'copy',
        root: destination,
        expectedHash: item.hash,
      );
    }
    var hasMetainfo = source != null;
    var recovered = false;
    for (final file in item.files) {
      if (p.extension(file.path).toLowerCase() != '.fastresume') continue;
      final archive = item.resumeArchivePath(file.path, destination);
      final needsResume = !hasMetainfo;
      final hash = item.hash;
      final (resume, digest) = await Isolate.run(() async {
        final handle = await File(file.path).open();
        late Uint8List bytes;
        try {
          const limit = 64 * 1024 * 1024;
          final length = await handle.length();
          if (length > limit) {
            throw const FormatException('qBittorrent resume exceeds 64 MiB');
          }
          bytes = await handle.read(length);
          if (bytes.length != length || await handle.length() != length) {
            throw const FormatException(
              'qBittorrent resume changed during read',
            );
          }
        } finally {
          await handle.close();
        }
        QbittorrentResume? resume;
        try {
          resume = QbittorrentResume.parse(bytes, hash);
        } on FormatException {
          if (needsResume) rethrow;
        }
        final digest = sha256.convert(bytes).toString();
        await _writeQbittorrentBackup(archive, bytes);
        if ((await sha256OfFile(archive)).toString() != digest) {
          throw StateError('qBittorrent resume archive verification failed');
        }
        return (resume, digest);
      });
      if (resume == null) continue;
      if (!hasMetainfo && resume.metainfo != null) {
        final torrent = p.join(
          destination,
          hash.substring(0, 2),
          '$hash.torrent',
        );
        await _writeQbittorrentBackup(torrent, resume.metainfo!);
        await _importFile(
          torrent,
          mode: 'copy',
          root: destination,
          expectedHash: hash,
        );
        hasMetainfo = true;
      }
      await repository.importQbittorrentResume(
        resume,
        archive,
        digest,
        missingMetainfo: !hasMetainfo,
      );
      recovered = true;
    }
    if (!hasMetainfo && !recovered) {
      throw const QbittorrentImportException(
        QbittorrentImportProblem.missingMetainfo,
      );
    }
  }

  Future<void> _verifyQbittorrentItem(String hash, String destination) async {
    final entry = await repository.get(hash);
    if (entry == null) {
      throw StateError('Imported torrent is not durably stored: $hash');
    }
    if (entry.torrentPath.isEmpty && entry.sourceUri != null) {
      final proof = (await repository.db.query(
        'torrents',
        columns: ['qbittorrent_resume_path', 'qbittorrent_resume_digest'],
        where: 'hash = ?',
        whereArgs: [hash],
        limit: 1,
      )).single;
      final archive = proof['qbittorrent_resume_path'] as String?;
      if (archive == null ||
          !p.isWithin(destination, archive) ||
          MagnetLink.parse(entry.sourceUri!).hash != hash) {
        throw StateError(
          'Recovered qBittorrent entry is not durably stored: $hash',
        );
      }
      final digest = await sha256OfFile(archive);
      if (digest.toString() != proof['qbittorrent_resume_digest']) {
        throw StateError(
          'Recovered qBittorrent resume verification failed: $hash',
        );
      }
      return;
    }
    if (!p.isWithin(destination, entry.torrentPath)) {
      throw StateError('Imported torrent is not durably stored: $hash');
    }
    final path = entry.torrentPath;
    final metainfo = await Isolate.run(() => _readTorrent(path));
    if (metainfo.hash != hash) {
      throw StateError('Imported torrent verification failed: $hash');
    }
  }

  Future<void> initialize() async {
    if (_initialized) return;
    if (_initializing != null) return _initializing!;
    final future = _initialize();
    _initializing = future;
    try {
      await future;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _initialize() async {
    _prefs = await SharedPreferences.getInstance();
    repository = TorrentRepository(
      await SqliteDatabaseProvider().getDatabase(),
    );
    await repository.initialize();
    _importSchemaVersion = TorrentRepository.schemaVersion;
    _stateDirectory = p.join(
      (await getApplicationSupportDirectory()).path,
      'torrent',
    );
    await Directory(_stateDirectory).create(recursive: true);
    if (!_prefs.containsKey('torrent.scanRoots')) {
      await _prefs.setStringList(
        'torrent.scanRoots',
        await discoverScanRoots(),
      );
    }
    _initialized = true;
    if (!const bool.fromEnvironment('CB_E2E')) {
      _pollTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(sync()),
      );
      _scanTimer = Timer.periodic(
        const Duration(minutes: 5),
        (_) => _autoScan(),
      );
      _autoScan();
      unawaited(sync());
    }
  }

  void _autoScan() {
    if (_importRefresh == null &&
        autoImport &&
        (storageMode == 'index' || libraryDirectory != null) &&
        !scan.running) {
      unawaited(
        refreshImports().catchError((Object error) {
          lastError = error.toString();
          notifyListeners();
        }),
      );
    }
  }

  Future<List<String>> discoverScanRoots() =>
      (_sourceDiscovery ?? TorrentSourceDiscovery.discover)();

  /// F5 explicitly imports fresh sources even when periodic import is disabled.
  Future<void> refreshImports() async {
    if (_importRefresh != null) return _importRefresh!;
    final job = _refreshImports();
    _importRefresh = job;
    try {
      await job;
    } finally {
      _importRefresh = null;
    }
  }

  Future<void> _refreshImports() async {
    await initialize();
    // Migrate once per schema version, including a service retained by hot
    // reload. Ordinary F5 must not repeat schema/index maintenance.
    if (_importSchemaVersion != TorrentRepository.schemaVersion) {
      await repository.initialize();
      _importSchemaVersion = TorrentRepository.schemaVersion;
    }
    final discovered = await discoverScanRoots();
    // A manual refresh waits for an existing import, then scans once more so
    // files created during the first pass are included. Repeated F5 coalesces.
    if (scan.running) await _scanDone?.future;
    final roots = {...scanRoots, ...discovered};
    await _runScan(roots: roots.toList(), newOnly: true);
  }

  Future<void> setLibraryDirectory(
    String value, {
    TorrentMovePlan? approvedMove,
  }) async {
    if (scan.running) {
      throw StateError('Stop the scan before changing storage folder');
    }
    final destination = p.normalize(p.absolute(value));
    final move = storageMode == 'move'
        ? await _requireMoveApproval(approvedMove, destination)
        : null;
    await Directory(destination).create(recursive: true);
    await _prefs.setString('torrent.libraryDirectory', destination);
    notifyListeners();
    if (move != null) {
      await _moveApproved(move);
    } else if (storageMode == 'copy') {
      await organizeLibrary();
    }
  }

  Future<void> setStorageMode(
    String value, {
    TorrentMovePlan? approvedMove,
  }) async {
    if (!const ['index', 'copy', 'move'].contains(value)) {
      throw ArgumentError.value(value);
    }
    if (scan.running) {
      throw StateError('Stop the scan before changing storage mode');
    }
    TorrentMovePlan? move;
    if (value == 'move') {
      final destination = approvedMove?.destination ?? libraryDirectory;
      if (destination == null) {
        throw StateError('Choose a torrent storage folder first');
      }
      move = await _requireMoveApproval(approvedMove, destination);
      await Directory(move.destination).create(recursive: true);
      await _prefs.setString('torrent.libraryDirectory', move.destination);
    }
    await _prefs.setString('torrent.storageMode', value);
    notifyListeners();
    if (move != null) {
      await _moveApproved(move);
    } else if (value == 'copy' && libraryDirectory != null) {
      await organizeLibrary();
    }
  }

  /// Applies the selected storage policy to files already in the index too.
  Future<void> organizeLibrary({TorrentMovePlan? approvedMove}) async {
    if (storageMode == 'index') return;
    if (storageMode == 'move') {
      final destination = libraryDirectory;
      if (destination == null) {
        throw StateError('Choose a torrent storage folder first');
      }
      await _moveApproved(
        await _requireMoveApproval(approvedMove, destination),
      );
    } else {
      await _runScan(organizeExisting: true);
    }
  }

  Future<TorrentMovePlan> previewMove({String? destination}) async {
    await initialize();
    if (scan.running) throw StateError('Stop the scan before organizing files');
    final folder = destination ?? libraryDirectory;
    if (folder == null) {
      throw StateError('Choose a torrent storage folder first');
    }
    final root = p.normalize(p.absolute(folder));
    final sources = <TorrentMoveSource>[];
    final seen = <String>{};
    Future<void> include(String path, String hash) async {
      final normalized = p.normalize(p.absolute(path));
      final target = p.join(root, hash.substring(0, 2), '$hash.torrent');
      final key = Platform.isWindows ? normalized.toLowerCase() : normalized;
      if (p.equals(normalized, target) || !seen.add(key)) return;
      final stat = await File(normalized).stat();
      if (stat.type != FileSystemEntityType.file) return;
      sources.add(
        TorrentMoveSource(
          path: normalized,
          destination: target,
          hash: hash,
          modified: stat.modified.microsecondsSinceEpoch,
          size: stat.size,
        ),
      );
    }

    await for (final file in repository.storedFiles()) {
      await include(file.path, file.hash);
    }
    await for (final source in repository.scanSources()) {
      await include(source['path'] as String, source['hash'] as String);
    }
    return TorrentMovePlan(
      destination: root,
      previousMode: storageMode,
      previousDirectory: libraryDirectory,
      sources: sources,
    );
  }

  Future<TorrentMovePlan> _requireMoveApproval(
    TorrentMovePlan? approved,
    String destination,
  ) async {
    final root = p.normalize(p.absolute(destination));
    if (approved == null) {
      final preview = await previewMove(destination: root);
      if (preview.sources.isNotEmpty) {
        throw StateError(
          'Confirm the source cleanup preview before moving files',
        );
      }
      return preview;
    }
    if (!p.equals(approved.destination, root) ||
        approved.previousMode != storageMode ||
        approved.previousDirectory != libraryDirectory) {
      throw StateError('Storage changed; review the source cleanup again');
    }
    return approved;
  }

  Future<void> _moveApproved(TorrentMovePlan plan) => _runScan(
    files: plan.sources.map((source) => source.path).toList(),
    approvedMove: plan,
  );

  Future<void> setExecutable(String value) async {
    if (_engine.running) {
      throw StateError('Restart the app before changing the running engine');
    }
    await _prefs.setString('torrent.executable', value);
    lastError = null;
    notifyListeners();
  }

  Future<void> setAutoImport(bool enabled) async {
    await _prefs.setBool('torrent.autoImport', enabled);
    notifyListeners();
    if (enabled) {
      _autoScan();
    } else {
      cancelScan();
    }
  }

  Future<void> setShowDownloadDialog(bool enabled) async {
    await _prefs.setBool('torrent.showDownloadDialog', enabled);
    notifyListeners();
  }

  Future<void> setReceiveInBackground(bool enabled) async {
    await _prefs.setBool('torrent.receiveInBackground', enabled);
    notifyListeners();
  }

  Future<bool> shouldReceiveInBackground() async {
    // File associations may target a different app window from Settings.
    final prefs = _initialized ? _prefs : await SharedPreferences.getInstance();
    await reloadTorrentPreferences(prefs);
    return prefs.getBool('torrent.receiveInBackground') ?? false;
  }

  String? get backgroundDownloadDirectory {
    final saved = defaultDownloadDirectory;
    if (saved != null && saved.isNotEmpty) return saved;
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    return home == null ? null : p.join(home, 'Downloads');
  }

  Future<T> _backgroundAction<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _backgroundImports = _backgroundImports.then((_) async {
      try {
        await initialize();
        // Settings can be saved in another app window/process. Refresh for
        // each queued import so cached defaults cannot start an unwanted task
        // or override the user's chosen payload folder.
        await reloadTorrentPreferences(_prefs);
        result.complete(await action());
      } catch (e, stack) {
        result.completeError(e, stack);
      }
    });
    return result.future;
  }

  /// [existed] reports whether the library already held this torrent before
  /// the source was received, so the notice can say so.
  Future<({TorrentEntry entry, bool existed})> openSourceInBackground(
    String source,
  ) => _backgroundAction(() async {
    final opened = await _openSource(source);
    return (
      entry: await _downloadInBackground(opened.entry),
      existed: opened.existed,
    );
  });

  Future<TorrentEntry> downloadInBackground(TorrentEntry entry) =>
      _backgroundAction(() => _downloadInBackground(entry));

  Future<TorrentEntry> _downloadInBackground(TorrentEntry entry) async {
    final current = await repository.get(entry.hash);
    if (current == null) throw StateError('Torrent was removed');
    // A repeated browser open must not resume, pause or restart existing tasks.
    if (const [
      'active',
      'waiting',
      'paused',
      'complete',
    ].contains(current.status)) {
      return current;
    }
    try {
      final destination = current.downloadDir ?? backgroundDownloadDirectory;
      if (destination == null ||
          !p.isAbsolute(destination) ||
          destination.contains('\x00')) {
        throw const FormatException(
          'Choose a default torrent download folder in Settings',
        );
      }
      await download(
        current,
        p.normalize(destination),
        startImmediately: startDownloadsImmediately,
      );
      return (await repository.get(current.hash))!;
    } catch (e) {
      await repository.update(current.hash, {'status': 'error', 'error': '$e'});
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setStartDownloadsImmediately(bool enabled) async {
    await _prefs.setBool('torrent.startImmediately', enabled);
    notifyListeners();
  }

  Future<void> setDefaultDownloadDirectory(String value) async {
    final directory = value.trim();
    if (directory.isEmpty) {
      await _prefs.remove('torrent.lastDownloadDirectory');
    } else {
      if (!p.isAbsolute(directory) || directory.contains('\x00')) {
        throw const FormatException(
          'An absolute download directory is required',
        );
      }
      await _prefs.setString(
        'torrent.lastDownloadDirectory',
        p.normalize(directory),
      );
    }
    notifyListeners();
  }

  Future<void> setScanRoots(List<String> roots) async {
    await _prefs.setStringList('torrent.scanRoots', roots.toSet().toList());
    notifyListeners();
  }

  Future<List<String>> systemRoots() async =>
      (await DriveInventoryService.load())
          .where(
            (drive) =>
                drive.kind != DriveKind.optical &&
                drive.kind != DriveKind.network,
          )
          .map((drive) => drive.path)
          .toList();

  /// Organizes metainfo according to the user's chosen mode. Only explicit
  /// download actions ever contact trackers/peers.
  Future<bool> importFile(
    String source, {
    TorrentMoveSource? approvedSource,
    TorrentMergeConfirmation? onDuplicate,
  }) async {
    await _ensureImportSchema();
    final inserted = await _importFile(
      source,
      mode: storageMode,
      root: libraryDirectory,
      approvedSource: approvedSource,
      onDuplicate: onDuplicate,
    );
    // Individual imports refresh already mounted library tabs immediately.
    // Scans still publish their throttled progress instead of per-file events.
    if (!scan.running) notifyListeners();
    return inserted;
  }

  Future<bool> _importFile(
    String source, {
    required String mode,
    required String? root,
    TorrentMoveSource? approvedSource,
    String? expectedHash,
    TorrentMergeConfirmation? onDuplicate,
    bool captureSource = false,
  }) async {
    // Hold validated bytes across a confirmation dialog. Browser-managed temp
    // files may disappear, change, or become inaccessible while it is open.
    final snapshot = onDuplicate != null || captureSource
        ? await Isolate.run(() async {
            final stat = await File(source).stat();
            final bytes = await _readTorrentBytes(source);
            return (
              info: await TorrentMetainfo.parseAsync(bytes),
              bytes: bytes,
              stat: stat,
            );
          })
        : null;
    if (snapshot != null) {
      await _approveImport(snapshot.info.hash, onDuplicate);
      expectedHash ??= snapshot.info.hash;
    }
    if (mode != 'index' && root == null) {
      throw StateError('Choose a torrent storage folder first');
    }
    final normalized = p.normalize(p.absolute(source));
    if (approvedSource != null &&
        await repository.get(approvedSource.hash) == null) {
      throw StateError('Torrent was removed after confirmation: $source');
    }
    // One worker per new file, including copy/verification, rather than
    // starting a new isolate for every read of the same metainfo.
    final (info, archive, stat) = await Isolate.run(() async {
      final file = File(source);
      final stat = snapshot?.stat ?? await file.stat();
      if (approvedSource != null &&
          (!p.equals(normalized, approvedSource.path) ||
              stat.modified.microsecondsSinceEpoch != approvedSource.modified ||
              stat.size != approvedSource.size)) {
        throw StateError('Source changed after confirmation: $source');
      }
      final info = snapshot?.info ?? await _readTorrent(source);
      if (expectedHash != null && info.hash != expectedHash) {
        throw StateError('qBittorrent source hash mismatch: $source');
      }
      if (approvedSource != null && info.hash != approvedSource.hash) {
        throw StateError('Source torrent changed after confirmation: $source');
      }
      final archive = mode == 'index'
          ? normalized
          : p.join(root!, info.hash.substring(0, 2), '${info.hash}.torrent');
      if (approvedSource != null &&
          !p.equals(archive, approvedSource.destination)) {
        throw StateError('Destination changed after confirmation: $source');
      }
      if (mode != 'index') {
        await Directory(p.dirname(archive)).create(recursive: true);
      }
      if (mode != 'index' && !await File(archive).exists()) {
        // Concurrent importers may share a hash. Unique temporary files and an
        // atomic rename prevent partially written metainfo becoming visible.
        final temporary =
            '$archive.${DateTime.now().microsecondsSinceEpoch}.tmp';
        try {
          if (snapshot != null) {
            await File(temporary).writeAsBytes(snapshot.bytes, flush: true);
          } else {
            await file.copy(temporary);
          }
          await File(temporary).setLastModified(stat.modified);
          final copied = await _readTorrent(temporary);
          if (copied.hash != info.hash) {
            throw StateError('Torrent changed during import: $source');
          }
          if (!await File(archive).exists()) {
            await File(temporary).rename(archive);
          }
        } finally {
          if (await File(temporary).exists()) await File(temporary).delete();
        }
      }
      if (mode != 'index') {
        final archived = await _readTorrent(archive);
        if (archived.hash != info.hash) {
          throw StateError('Stored torrent is corrupt: $archive');
        }
      }
      return (info, archive, stat);
    });
    final inserted = await repository.import(
      info,
      archive,
      normalized,
      stat.modified.microsecondsSinceEpoch,
      stat.size,
    );
    if (onDuplicate != null) {
      await repository.update(info.hash, {
        'modified_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
    if (mode != 'index' && !p.equals(normalized, archive)) {
      final archivedStat = await File(archive).stat();
      await repository.recordSource(
        info.hash,
        archive,
        archivedStat.modified.microsecondsSinceEpoch,
        archivedStat.size,
      );
    }
    if (mode == 'move' && !p.equals(normalized, archive)) {
      // Only remove the source after both the verified copy and durable index
      // exist, and only under the mode explicitly selected in the UI.
      final file = File(source);
      final currentStat = await file.stat();
      if (currentStat.size != stat.size ||
          currentStat.modified != stat.modified) {
        throw StateError('Source changed before move: $source');
      }
      await file.delete();
    }
    return inserted;
  }

  void cancelScan() {
    _cancelScan = true;
  }

  Future<void> importFiles(
    List<String> files, {
    TorrentMergeConfirmation? onDuplicate,
  }) => _runScan(files: files, onDuplicate: onDuplicate);
  Future<void> scanDirectories(List<String> roots) =>
      _runScan(roots: roots, organizeExisting: storageMode == 'copy');

  Future<void> _runScan({
    List<String> roots = const [],
    List<String> files = const [],
    bool organizeExisting = false,
    bool newOnly = false,
    TorrentMovePlan? approvedMove,
    TorrentMergeConfirmation? onDuplicate,
  }) async {
    await initialize();
    if (scan.running) throw StateError('A torrent scan is already running');
    if (storageMode != 'index' && libraryDirectory == null) {
      throw StateError('Choose a torrent storage folder first');
    }
    final completion = _scanDone = Completer<void>();
    _currentScanLog = null;
    _cancelScan = false;
    var visited = 0, imported = 0, duplicates = 0, failed = 0;
    var current = '';
    final errors = <String>[];
    String pathKey(String path) => Platform.isWindows
        ? p.normalize(p.absolute(path)).toLowerCase()
        : p.normalize(p.absolute(path));
    final known = <String, _ScanSource>{};
    final names = <String, List<_ScanSource>>{};
    final visitedPaths = <String>{};
    final archives = <String, bool>{};
    final refreshNames = <String>{};
    final approvedSources = {
      for (final source in approvedMove?.sources ?? const <TorrentMoveSource>[])
        pathKey(source.path): source,
    };
    void remember(Map<String, Object?> row) {
      final source = (
        path: row['path'] as String,
        archive: row['torrent_path'] as String,
        modified: row['modified'] as int,
        size: row['size'] as int,
        version: row['metainfo_version'] as int,
      );
      known[pathKey(source.path)] = source;
      names
          .putIfAbsent(p.basename(source.path).toLowerCase(), () => [])
          .add(source);
    }

    Future<bool> usableArchive(_ScanSource source) async {
      if (source.version != 1 ||
          (storageMode != 'index' &&
              !p.isWithin(libraryDirectory!, source.archive))) {
        return false;
      }
      final key = pathKey(source.archive);
      return archives[key] ??= await File(source.archive).exists();
    }

    final log = File(scanLogPath).openWrite();
    var lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    void publish({bool running = true}) {
      final now = DateTime.now();
      if (running && now.difference(lastUpdate).inMilliseconds < 200) return;
      lastUpdate = now;
      scan = TorrentScanProgress(
        running: running,
        visited: visited,
        imported: imported,
        duplicates: duplicates,
        failed: failed,
        currentPath: current,
        errors: List.unmodifiable(errors),
        cancelled: _cancelScan,
      );
      notifyListeners();
    }

    void failure(String path, Object error) {
      failed++;
      final message = '$path: $error';
      if (errors.length < 100) errors.add(message);
      log.writeln(message);
    }

    Future<void> visitFile(String path) async {
      if (_cancelScan || !visitedPaths.add(pathKey(path))) return;
      current = path;
      visited++;
      try {
        final filename = p.basename(path).toLowerCase();
        if (newOnly && refreshNames.contains(filename)) {
          duplicates++;
          publish();
          return;
        }
        final normalized = p.normalize(p.absolute(path));
        final existing = known[pathKey(normalized)];
        // Name duplicates from another folder can skip parsing entirely.
        // Move must still verify content before removing any source file.
        if (onDuplicate == null &&
            !newOnly &&
            existing == null &&
            storageMode != 'move') {
          for (final candidate
              in names[p.basename(path).toLowerCase()] ??
                  const <_ScanSource>[]) {
            if (await usableArchive(candidate)) {
              duplicates++;
              publish();
              return;
            }
          }
        }
        if (!newOnly && onDuplicate == null) {
          final stat = await File(path).stat();
          if (existing != null &&
              existing.modified == stat.modified.microsecondsSinceEpoch &&
              existing.size == stat.size &&
              (storageMode != 'move' ||
                  pathKey(normalized) == pathKey(existing.archive))) {
            if (await usableArchive(existing)) {
              duplicates++;
              publish();
              return;
            }
          }
        }
        if (await importFile(
          path,
          approvedSource: approvedSources[pathKey(path)],
          onDuplicate: onDuplicate,
        )) {
          imported++;
        } else {
          duplicates++;
        }
        if (newOnly) {
          refreshNames.add(filename);
        } else {
          archives.clear();
          final rows = await repository.db.rawQuery(
            '''SELECT s.path, s.modified, s.size, t.torrent_path, t.metainfo_version
          FROM torrent_sources s JOIN torrents t ON t.hash = s.hash
          WHERE s.path = ?''',
            [normalized],
          );
          for (final row in rows) {
            remember(row);
          }
        }
      } on TorrentImportCancelled {
        duplicates++;
      } catch (e) {
        failure(path, e);
      }
      publish();
    }

    Future<void> visitDirectory(String path, int depth) async {
      if (_cancelScan) return;
      if (depth > 128) {
        failure(path, 'Directory nesting exceeds 128');
        return;
      }
      // Archive folders are scanned too: a chosen destination may contain
      // originals, or may be the only recoverable metainfo after DB restore.
      // Content identity makes re-import idempotent, including in move mode.
      current = path;
      publish();
      try {
        // Quick refresh uses one native recursive listing per source rather
        // than opening/awaiting a separate Dart stream for every subfolder.
        final entries = Directory(path)
            .list(recursive: newOnly, followLinks: false)
            .handleError((Object error) {
              failure(
                error is FileSystemException ? error.path ?? path : path,
                error,
              );
            });
        await for (final entity in entries) {
          if (_cancelScan) break;
          if (entity is Directory && !newOnly) {
            await visitDirectory(entity.path, depth + 1);
          } else if (entity is File &&
              p.extension(entity.path).toLowerCase() == '.torrent') {
            await visitFile(entity.path);
          }
        }
      } catch (e) {
        failure(path, e);
      }
    }

    publish();
    try {
      if (newOnly) {
        refreshNames.addAll(await repository.knownFileNames());
      } else {
        await for (final row in repository.scanSources()) {
          if (_cancelScan) break;
          remember(row);
        }
      }
      if (organizeExisting) {
        // Include old indexed locations even when they are outside scan roots.
        // In move mode this also removes verified original copies left by a
        // previous copy/index policy.
        await for (final path in repository.storedPaths()) {
          if (_cancelScan) break;
          if (await File(path).exists()) await visitFile(path);
        }
        for (final source in known.values.toList()) {
          if (_cancelScan) break;
          if (await File(source.path).exists()) await visitFile(source.path);
        }
      }
      final unique = roots
          .map((r) => p.normalize(p.absolute(r)))
          .toSet()
          .toList();
      for (final root in unique) {
        if (unique.any((other) => other != root && p.isWithin(other, root))) {
          continue;
        }
        await visitDirectory(root, 0);
      }
      for (final file in files) {
        if (_cancelScan) break;
        await visitFile(file);
      }
    } catch (e) {
      failure(current, e);
    } finally {
      try {
        await log.flush();
        await log.close();
      } finally {
        publish(running: false);
        completion.complete();
      }
    }
  }

  /// User actions take the engine over from another window; background sync
  /// passes `takeOver: false` so idle windows never pull downloads back.
  Future<void> _ensureEngine({bool takeOver = true}) => _engine.start(
    _stateDirectory,
    executable: executable,
    takeOver: takeOver,
  );

  /// Runs this window's pending downloads here, taking them over from another
  /// window: the most recently opened torrent tab wins.
  Future<void> claimEngine() async {
    await initialize();
    if (_engine.running || (await repository.pending(limit: 1)).isEmpty) {
      return;
    }
    try {
      await _ensureEngine();
    } catch (e) {
      lastError = e.toString();
      notifyListeners();
      return;
    }
    await sync();
  }

  Future<void> _approveImport(
    String hash,
    TorrentMergeConfirmation? onDuplicate,
  ) async {
    if (onDuplicate == null) return;
    final existing = await repository.get(hash);
    if (existing != null && !await onDuplicate(existing)) {
      throw const TorrentImportCancelled();
    }
  }

  Future<void> _ensureImportSchema() async {
    await initialize();
    if (_importSchemaVersion != TorrentRepository.schemaVersion) {
      await repository.initialize();
      _importSchemaVersion = TorrentRepository.schemaVersion;
    }
  }

  Future<TorrentEntry> importMagnet(
    String uri, {
    TorrentMergeConfirmation? onDuplicate,
  }) async => (await _importMagnet(uri, onDuplicate: onDuplicate)).entry;

  Future<({TorrentEntry entry, bool existed})> _importMagnet(
    String uri, {
    TorrentMergeConfirmation? onDuplicate,
  }) async {
    await _ensureImportSchema();
    final link = MagnetLink.parse(uri);
    await _approveImport(link.hash, onDuplicate);
    final existed = await repository.get(link.hash) != null;
    final entry = await repository.importMagnet(link, touch: true);
    notifyListeners();
    return (entry: entry, existed: existed);
  }

  Future<TorrentEntry> openSource(
    String source, {
    TorrentMergeConfirmation? onDuplicate,
  }) async => (await _openSource(source, onDuplicate: onDuplicate)).entry;

  Future<({TorrentEntry entry, bool existed})> _openSource(
    String source, {
    TorrentMergeConfirmation? onDuplicate,
  }) async {
    if (!TorrentLaunchRequest.isSource(source)) {
      throw const FormatException('Invalid torrent source');
    }
    if (source.toLowerCase().startsWith('magnet:')) {
      return _importMagnet(source, onDuplicate: onDuplicate);
    }
    final normalized = p.normalize(p.absolute(source));
    await _ensureImportSchema();
    // A browser can save private-session files anywhere, including Downloads.
    // Opening a file must capture durable metainfo without deleting or relying
    // on the browser-owned source. Explicit imports/scans retain the selected
    // index/copy/move policy.
    final inserted = await _importFile(
      source,
      mode: 'copy',
      root: storageMode == 'index' || libraryDirectory == null
          ? p.join(_stateDirectory, 'opened-torrents')
          : libraryDirectory,
      onDuplicate: onDuplicate,
      captureSource: true,
    );
    final rows = await repository.db.query(
      'torrent_sources',
      columns: ['hash'],
      where: 'path = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    final entry = await repository.get(rows.single['hash'] as String);
    notifyListeners();
    return (entry: entry!, existed: !inserted);
  }

  /// HTTP links fetch only metainfo. Payload transfer still requires the
  /// destination/start dialog, exactly as when opening a local torrent.
  Future<TorrentEntry> openLink(
    String source, {
    TorrentMergeConfirmation? onDuplicate,
  }) async {
    final value = source.trim();
    if (value.toLowerCase().startsWith('magnet:')) {
      return importMagnet(value, onDuplicate: onDuplicate);
    }
    final uri = Uri.tryParse(value);
    if (value.length > 32768 ||
        value.contains(RegExp(r'[\x00-\x1f]')) ||
        uri == null ||
        !const ['http', 'https'].contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty) {
      throw const FormatException('Enter an HTTP, HTTPS or magnet link');
    }
    await _ensureImportSchema();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    final bytes = BytesBuilder(copy: false);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 20));
      request.maxRedirects = 5;
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/x-bittorrent, application/octet-stream',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      const limit = 16 * 1024 * 1024;
      if (response.contentLength > limit) {
        throw const FormatException('Torrent exceeds 16 MiB');
      }
      final watch = Stopwatch()..start();
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        if (watch.elapsed > const Duration(seconds: 60)) {
          throw TimeoutException('Torrent link timed out');
        }
        if (bytes.length + chunk.length > limit) {
          throw const FormatException('Torrent exceeds 16 MiB');
        }
        bytes.add(chunk);
      }
    } finally {
      client.close(force: true);
    }
    final data = bytes.takeBytes();
    final info = await TorrentMetainfo.parseAsync(data);
    await _approveImport(info.hash, onDuplicate);
    final directory = Directory(p.join(_stateDirectory, 'link-imports'));
    await directory.create(recursive: true);
    final target = File(p.join(directory.path, '${info.hash}.torrent'));
    final temporary = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporary.writeAsBytes(data, flush: true);
      // The filename is derived from validated metainfo, never URL headers.
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    if (receiveInBackground) {
      await openSource(target.path);
    } else {
      await importFile(target.path);
    }
    await repository.recordSourceUri(info.hash, value);
    await repository.update(info.hash, {
      'modified_at': DateTime.now().millisecondsSinceEpoch,
    });
    notifyListeners();
    return (await repository.get(info.hash))!;
  }

  Future<void> _addTask(
    TorrentEntry entry,
    String destination,
    String gid, {
    bool paused = false,
  }) async {
    if (entry.torrentPath.isNotEmpty) {
      await _engine.add(
        entry.torrentPath,
        destination,
        gid,
        paused: paused,
        expectedHash: entry.hash,
      );
    } else {
      await _engine.addMagnet(
        entry.sourceUri!,
        destination,
        gid,
        paused: paused,
      );
    }
  }

  Future<void> _action(
    String hash,
    Future<void> Function(TorrentEntry) action,
  ) async {
    while (!_actions.add(hash)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    try {
      final current = await repository.get(hash);
      if (current == null) return;
      await action(current);
      lastError = null;
    } finally {
      _actions.remove(hash);
      notifyListeners();
    }
  }

  Future<void> download(
    TorrentEntry entry,
    String destination, {
    bool startImmediately = true,
  }) => _action(entry.hash, (entry) async {
    if (entry.status == 'active' || entry.status == 'waiting') {
      throw StateError(
        'Stop this torrent before choosing a different destination',
      );
    }
    await Directory(destination).create(recursive: true);
    await _validateEntry(entry);
    await _ensureEngine();
    // A paused task may be saved to a different destination. Remove its engine
    // task under the same action lock; existing payloads remain on disk.
    if (entry.status == 'paused') await _stop(entry);
    final gid = entry.hash.substring(0, 16);
    // Discard an old terminal result with this deterministic GID before retry.
    try {
      await _engine.call('removeDownloadResult', [gid]);
    } on Aria2RpcException catch (_) {}
    await repository.update(entry.hash, {
      'gid': gid,
      'download_dir': destination,
      if (entry.downloadDir != null &&
          !p.equals(p.normalize(entry.downloadDir!), p.normalize(destination)))
        'completed_bytes': 0,
      'status': startImmediately ? 'waiting' : 'paused',
      ..._idleNetwork,
      'error': null,
    });
    await _addTask(entry, destination, gid, paused: !startImmediately);
  });

  Future<void> pause(TorrentEntry entry) => _action(entry.hash, (entry) async {
    if (entry.status != 'active' && entry.status != 'waiting') return;
    await _ensureEngine();
    final task = await _ensureTask(entry);
    await _engine.call('pause', [task['gid'] ?? entry.gid]);
    await repository.update(entry.hash, {'status': 'paused', ..._idleNetwork});
  });

  Future<void> resume(TorrentEntry entry) => _action(entry.hash, (entry) async {
    if (entry.status != 'paused') return;
    await _ensureEngine();
    final task = await _ensureTask(entry);
    await _engine.call('unpause', [task['gid'] ?? entry.gid]);
    await repository.update(entry.hash, {
      'status': 'waiting',
      'error': null,
      ..._idleNetwork,
    });
  });

  Future<void> stop(TorrentEntry entry) => _action(entry.hash, _stop);

  Future<void> _stop(TorrentEntry entry) async {
    // A second window must acquire ownership before changing task intent.
    // Otherwise it could remove the index while the owning engine keeps
    // downloading an untracked torrent.
    if (entry.gid != null &&
        !_engine.running &&
        const ['active', 'waiting', 'paused'].contains(entry.status)) {
      await _ensureEngine();
    }
    if (entry.gid != null && _engine.running) {
      var gid = entry.gid;
      try {
        final task =
            await _engine.call('tellStatus', [
                  gid,
                  ['followedBy'],
                ])
                as Map<String, dynamic>;
        final children = task['followedBy'] as List?;
        if (children != null && children.isNotEmpty) {
          gid = children.first as String;
        }
        await _engine.call('forceRemove', [gid]);
      } on Aria2RpcException catch (e) {
        if (e.message.contains('cannot be removed')) {
          final status =
              await _engine.call('tellStatus', [
                    gid,
                    ['status'],
                  ])
                  as Map<String, dynamic>;
          if (!const [
            'complete',
            'error',
            'removed',
          ].contains(status['status'])) {
            rethrow;
          }
        } else if (!e.message.contains('not found')) {
          rethrow;
        }
      }
      try {
        await _engine.call('removeDownloadResult', [gid]);
      } on Aria2RpcException catch (_) {}
    }
    await repository.update(entry.hash, {
      'status': 'library',
      'gid': null,
      ..._idleNetwork,
    });
  }

  Future<void> remove(TorrentEntry entry) => _action(entry.hash, (entry) async {
    await _stop(entry);
    await repository.remove(entry.hash);
    // Metainfo and downloaded files are retained on disk.
  });

  Future<void> _validateEntry(TorrentEntry entry) async {
    if (entry.torrentPath.isEmpty && entry.sourceUri != null) {
      if (MagnetLink.parse(entry.sourceUri!).hash != entry.hash) {
        throw const FormatException('Magnet info hash has changed');
      }
      return;
    }
    final info = await Isolate.run(() => _readTorrent(entry.torrentPath));
    if (info.hash != entry.hash) {
      throw const FormatException(
        'Torrent metainfo has changed; import it again',
      );
    }
  }

  Future<Map<String, dynamic>> _ensureTask(TorrentEntry entry) async {
    try {
      var gid = entry.gid!;
      for (var depth = 0; depth < 4; depth++) {
        final task =
            await _engine.call('tellStatus', [
                  gid,
                  [
                    'gid',
                    'status',
                    'completedLength',
                    'totalLength',
                    'downloadSpeed',
                    'uploadSpeed',
                    'uploadLength',
                    'numSeeders',
                    'connections',
                    'errorMessage',
                    'followedBy',
                    'bittorrent',
                  ],
                ])
                as Map<String, dynamic>;
        final children = task['followedBy'] as List?;
        if (children != null && children.isNotEmpty) {
          gid = children.first as String;
          await repository.update(entry.hash, {'gid': gid});
          continue;
        }
        return {...task, 'gid': gid};
      }
      throw const FormatException('Too many torrent metadata transitions');
    } on Aria2RpcException catch (e) {
      if (!e.message.contains('not found')) rethrow;
      await _validateEntry(entry);
      await _addTask(
        entry,
        entry.downloadDir!,
        entry.gid!,
        paused: entry.status == 'paused',
      );
      return {
        'status': entry.status,
        'completedLength': '${entry.completedBytes}',
        'downloadSpeed': '0',
      };
    }
  }

  Future<void> sync() async {
    if (!_initialized || _syncing) return;
    _syncing = true;
    var changed = false;
    try {
      if (_actions.isEmpty &&
          await _engine.releaseIfRequested(_stateDirectory)) {
        // A newer window took the downloads over.
        changed = true;
        return;
      }
      var after = '';
      while (true) {
        final entries = await repository.pending(after: after);
        if (entries.isEmpty) break;
        if (!_engine.running) {
          try {
            await _ensureEngine(takeOver: false);
          } on Aria2EngineOwnedElsewhere {
            // The owning window writes progress to the shared database;
            // refresh this window's view of it.
            changed = true;
            break;
          }
        }
        for (final entry in entries) {
          after = entry.hash;
          if (_actions.contains(entry.hash)) continue;
          // Reserve the same per-torrent lock as UI actions, preventing a
          // delayed status reply from undoing pause/stop/remove.
          _actions.add(entry.hash);
          try {
            final status = await _ensureTask(entry);
            final state = status['status'] as String;
            final torrent = status['bittorrent'] as Map?;
            final info = torrent?['info'] as Map?;
            await repository.update(entry.hash, {
              if (status['gid'] != null) 'gid': status['gid'] as String,
              if (status['totalLength'] != null &&
                  int.parse(status['totalLength'] as String) > 0)
                'total_bytes': int.parse(status['totalLength'] as String),
              if (info?['name'] is String) 'name': info!['name'] as String,
              'status': state == 'removed' ? 'library' : state,
              'completed_bytes': int.parse(status['completedLength'] as String),
              ..._idleNetwork,
              if (state == 'active') ...{
                'download_speed': int.parse(status['downloadSpeed'] as String),
                'upload_speed': int.tryParse('${status['uploadSpeed']}') ?? 0,
                // Missing engine measurements remain unknown, rather than 0.
                'seeders': int.tryParse('${status['numSeeders']}'),
                'connections': int.tryParse('${status['connections']}'),
              },
              if (status['uploadLength'] != null)
                'uploaded_bytes': int.parse(status['uploadLength'] as String),
              'error': state == 'error'
                  ? status['errorMessage'] as String?
                  : null,
            });
            changed = true;
          } catch (e) {
            if (e is Aria2RpcException ||
                e is FileSystemException ||
                e is FormatException) {
              await repository.update(entry.hash, {
                'status': 'error',
                ..._idleNetwork,
                'error': e.toString(),
              });
              changed = true;
            } else {
              rethrow;
            }
          } finally {
            _actions.remove(entry.hash);
          }
        }
      }
      if (lastError != null) {
        lastError = null;
        changed = true;
      }
    } catch (e) {
      if (lastError != e.toString()) {
        lastError = e.toString();
        changed = true;
      }
    } finally {
      _syncing = false;
      if (changed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scanTimer?.cancel();
    cancelScan();
    unawaited(_engine.dispose());
    super.dispose();
  }
}
