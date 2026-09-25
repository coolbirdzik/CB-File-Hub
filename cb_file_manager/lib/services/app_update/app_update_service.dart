import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_update/in_app_update.dart' as play;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import 'package:cb_file_manager/e2e/cb_e2e_config.dart';

import 'app_update_models.dart';
import 'desktop_update_installer.dart';
import 'github_release_source.dart';

/// Checks for, downloads and installs app updates.
///
/// * MSI / portable Windows builds and the macOS DMG download the release
///   asset from GitHub with visible progress, then install only after the
///   user confirms (see [installAndRestart]).
/// * The Microsoft Store build uses the Store's in-app update API: download
///   first, install (Windows closes the app) after the user confirms.
/// * The Google Play build uses Play's flexible in-app update flow: Play asks
///   for consent and downloads, the app then offers to restart.
class AppUpdateService extends ChangeNotifier {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  /// Lets a debug build exercise the updater:
  /// `--dart-define=CB_UPDATER_DEBUG=true`. Off by default so a debug run
  /// never overwrites its own build folder.
  static const bool _debugOverride = bool.fromEnvironment('CB_UPDATER_DEBUG');

  static const MethodChannel _storeChannel = MethodChannel(
    'cb_file_manager/store_update',
  );

  final GithubReleaseSource _github = GithubReleaseSource();

  Future<AppDistribution>? _distribution;
  String _currentVersion = '';

  AppUpdatePhase _phase = AppUpdatePhase.idle;
  AppUpdateInfo? _update;
  double? _progress;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _error;
  String? _packagePath;

  http.Client? _downloadClient;
  bool _cancelRequested = false;
  StreamSubscription<play.InstallStatus>? _playSubscription;

  AppUpdatePhase get phase => _phase;
  AppUpdateInfo? get update => _update;

  /// 0..1 while downloading; `null` when the source reports no progress.
  double? get progress => _progress;
  int get receivedBytes => _receivedBytes;
  int get totalBytes => _totalBytes;
  String? get error => _error;
  String get currentVersion => _currentVersion;

  bool get hasUpdate =>
      _update != null &&
      (_phase == AppUpdatePhase.available ||
          _phase == AppUpdatePhase.downloading ||
          _phase == AppUpdatePhase.readyToInstall ||
          _phase == AppUpdatePhase.installing);

  /// Direct-download builds can cancel; store downloads belong to the store.
  bool get canCancelDownload =>
      _phase == AppUpdatePhase.downloading &&
      _resolvedDistribution?.isSelfUpdating == true;

  AppDistribution? _resolvedDistribution;
  AppDistribution? get distribution => _resolvedDistribution;

  Future<AppDistribution> resolveDistribution() {
    return _distribution ??= _detectDistribution().then((value) {
      _resolvedDistribution = value;
      return value;
    });
  }

  Future<AppDistribution> _detectDistribution() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version.trim();
      if (kCbE2E || (kDebugMode && !_debugOverride)) {
        return AppDistribution.unsupported;
      }

      if (Platform.isAndroid) {
        return info.installerStore == 'com.android.vending'
            ? AppDistribution.googlePlay
            : AppDistribution.unsupported;
      }
      if (Platform.isWindows) {
        final packaged =
            await _storeChannel.invokeMethod<bool>('isPackaged') ?? false;
        if (packaged) return AppDistribution.microsoftStore;
        return _isUnderProgramFiles(Platform.resolvedExecutable)
            ? AppDistribution.windowsInstaller
            : AppDistribution.windowsPortable;
      }
      if (Platform.isMacOS) {
        final bundle = DesktopUpdateInstaller.macosBundlePath(
          Platform.resolvedExecutable,
        );
        // Running straight from the mounted DMG: nothing to replace.
        if (bundle == null || bundle.startsWith('/Volumes/')) {
          return AppDistribution.unsupported;
        }
        return AppDistribution.macosDmg;
      }
    } catch (e) {
      debugPrint('AppUpdateService: cannot detect distribution: $e');
    }
    return AppDistribution.unsupported;
  }

  static bool _isUnderProgramFiles(String executable) {
    final env = Platform.environment;
    final exeDir = p.dirname(executable).toLowerCase();
    return [
      env['ProgramFiles'],
      env['ProgramW6432'],
      env['ProgramFiles(x86)'],
    ].whereType<String>().any(
      (root) => root.isNotEmpty && p.isWithin(root.toLowerCase(), exeDir),
    );
  }

  /// Checks once in the background shortly after launch and calls
  /// [onUpdateFound] when a newer version exists.
  void scheduleStartupCheck(void Function(AppUpdateInfo update) onUpdateFound) {
    Timer(const Duration(seconds: 8), () async {
      final distribution = await resolveDistribution();
      if (distribution == AppDistribution.unsupported) return;
      await checkForUpdates(silent: true);
      final update = _update;
      if (update != null && hasUpdate) onUpdateFound(update);
    });
  }

  Future<void> checkForUpdates({bool silent = false}) async {
    if (_phase == AppUpdatePhase.checking ||
        _phase == AppUpdatePhase.downloading ||
        _phase == AppUpdatePhase.installing) {
      return;
    }
    // A finished download stays valid until the user installs it.
    if (_phase == AppUpdatePhase.readyToInstall) return;

    final distribution = await resolveDistribution();
    if (distribution == AppDistribution.unsupported) return;

    _setPhase(AppUpdatePhase.checking);
    try {
      switch (distribution) {
        case AppDistribution.windowsInstaller:
        case AppDistribution.windowsPortable:
        case AppDistribution.macosDmg:
          _update = await _github.fetchUpdate(
            currentVersion: _currentVersion,
            distribution: distribution,
          );
          _setPhase(
            _update == null
                ? AppUpdatePhase.upToDate
                : AppUpdatePhase.available,
          );
        case AppDistribution.microsoftStore:
          final result = await _storeChannel.invokeMapMethod<String, dynamic>(
            'checkForUpdates',
          );
          final count = (result?['count'] as int?) ?? 0;
          _update = count > 0
              ? AppUpdateInfo(version: (result?['version'] as String?) ?? '')
              : null;
          _setPhase(
            _update == null
                ? AppUpdatePhase.upToDate
                : AppUpdatePhase.available,
          );
        case AppDistribution.googlePlay:
          await _checkGooglePlay();
        case AppDistribution.unsupported:
          break;
      }
    } catch (e) {
      debugPrint('AppUpdateService: update check failed: $e');
      _update = null;
      if (silent) {
        _setPhase(AppUpdatePhase.idle);
      } else {
        _fail(e);
      }
    }
  }

  Future<void> _checkGooglePlay() async {
    final info = await play.InAppUpdate.checkForUpdate();
    final available =
        info.updateAvailability == play.UpdateAvailability.updateAvailable ||
        info.updateAvailability ==
            play.UpdateAvailability.developerTriggeredUpdateInProgress;
    if (!available) {
      _update = null;
      _setPhase(AppUpdatePhase.upToDate);
      return;
    }
    _update = const AppUpdateInfo(version: '');
    if (info.installStatus == play.InstallStatus.downloaded) {
      // Downloaded in an earlier session; only the restart is left.
      _setPhase(AppUpdatePhase.readyToInstall);
    } else if (info.installStatus == play.InstallStatus.downloading ||
        info.installStatus == play.InstallStatus.pending) {
      _listenToPlay();
      _progress = null;
      _setPhase(AppUpdatePhase.downloading);
    } else {
      _setPhase(AppUpdatePhase.available);
    }
  }

  Future<void> startDownload() async {
    final update = _update;
    final distribution = _resolvedDistribution;
    if (update == null ||
        distribution == null ||
        _phase == AppUpdatePhase.downloading) {
      return;
    }
    _error = null;
    _progress = distribution.isSelfUpdating ? 0 : null;
    _receivedBytes = 0;
    _totalBytes = update.assetSize ?? 0;
    _setPhase(AppUpdatePhase.downloading);

    try {
      switch (distribution) {
        case AppDistribution.windowsInstaller:
        case AppDistribution.windowsPortable:
        case AppDistribution.macosDmg:
          await _downloadAsset(update);
        case AppDistribution.microsoftStore:
          final state = await _runStoreRequest('download');
          if (state == 'completed') {
            _setPhase(AppUpdatePhase.readyToInstall);
          } else if (state == 'canceled') {
            _setPhase(AppUpdatePhase.available);
          } else {
            _fail(state);
          }
        case AppDistribution.googlePlay:
          _listenToPlay();
          final result = await play.InAppUpdate.startFlexibleUpdate();
          if (result == play.AppUpdateResult.userDeniedUpdate) {
            _setPhase(AppUpdatePhase.available);
          } else if (result == play.AppUpdateResult.inAppUpdateFailed) {
            _fail('Google Play update failed');
          } else if (_phase == AppUpdatePhase.downloading) {
            // startFlexibleUpdate completes once the download has finished.
            _setPhase(AppUpdatePhase.readyToInstall);
          }
        case AppDistribution.unsupported:
          _setPhase(AppUpdatePhase.idle);
      }
    } catch (e) {
      if (_cancelRequested) {
        _setPhase(AppUpdatePhase.available);
      } else {
        _fail(e);
      }
    } finally {
      _cancelRequested = false;
    }
  }

  void cancelDownload() {
    if (!canCancelDownload) return;
    _cancelRequested = true;
    _downloadClient?.close();
  }

  Future<void> _downloadAsset(AppUpdateInfo update) async {
    final url = update.downloadUrl;
    final name = update.assetName;
    if (url == null || name == null) {
      throw StateError('The release has no downloadable package');
    }
    final dir = Directory(
      p.join(Directory.systemTemp.path, 'cbfilehub-update'),
    );
    await dir.create(recursive: true);
    final target = File(p.join(dir.path, p.basename(name)));

    // Reuse a complete download from an earlier attempt.
    if (await target.exists() && await _isValidPackage(target, update)) {
      _receivedBytes = _totalBytes = await target.length();
      _progress = 1;
      _packagePath = target.path;
      _setPhase(AppUpdatePhase.readyToInstall);
      return;
    }

    final partial = File('${target.path}.part');
    final client = http.Client();
    _downloadClient = client;
    IOSink? sink;
    try {
      final response = await client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode != 200) {
        throw http.ClientException(
          'Download failed (HTTP ${response.statusCode})',
          Uri.parse(url),
        );
      }
      _totalBytes = response.contentLength ?? update.assetSize ?? 0;
      sink = partial.openWrite();
      var lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
      await for (final chunk in response.stream) {
        sink.add(chunk);
        _receivedBytes += chunk.length;
        if (_totalBytes > 0) {
          _progress = (_receivedBytes / _totalBytes).clamp(0.0, 1.0);
        }
        final now = DateTime.now();
        if (now.difference(lastNotify).inMilliseconds >= 100) {
          lastNotify = now;
          notifyListeners();
        }
      }
      await sink.close();
      sink = null;

      if (!await _isValidPackage(partial, update)) {
        throw StateError('The downloaded file is corrupted');
      }
      if (await target.exists()) await target.delete();
      await partial.rename(target.path);
      _packagePath = target.path;
      _progress = 1;
      _setPhase(AppUpdatePhase.readyToInstall);
    } finally {
      _downloadClient = null;
      client.close();
      await sink?.close();
      if (await partial.exists()) {
        try {
          await partial.delete();
        } catch (_) {}
      }
    }
  }

  static Future<bool> _isValidPackage(File file, AppUpdateInfo update) async {
    final size = update.assetSize;
    if (size != null && size > 0 && await file.length() != size) return false;
    final expected = update.sha256;
    if (expected == null || expected.isEmpty) return true;
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString() == expected;
  }

  /// Runs a Store download/install request, mirroring its progress.
  Future<String> _runStoreRequest(String method) async {
    final poll = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      try {
        final raw = await _storeChannel.invokeMethod<double>('getProgress');
        if (raw == null || _phase != AppUpdatePhase.downloading) return;
        // The Store reports 0–0.8 for the download and 0.8–1 for the install.
        _progress = (raw / 0.8).clamp(0.0, 1.0);
        notifyListeners();
      } catch (_) {}
    });
    try {
      return await _storeChannel.invokeMethod<String>(method) ?? 'otherError';
    } finally {
      poll.cancel();
    }
  }

  void _listenToPlay() {
    _playSubscription ??= play.InAppUpdate.installUpdateListener.listen((
      status,
    ) {
      switch (status) {
        case play.InstallStatus.pending:
        case play.InstallStatus.downloading:
          _progress = null;
          _setPhase(AppUpdatePhase.downloading);
        case play.InstallStatus.downloaded:
          _setPhase(AppUpdatePhase.readyToInstall);
        case play.InstallStatus.failed:
          _fail('Google Play update failed');
        case play.InstallStatus.canceled:
          _setPhase(AppUpdatePhase.available);
        case play.InstallStatus.installing:
        case play.InstallStatus.installed:
        case play.InstallStatus.unknown:
          break;
      }
    }, onError: (Object e) => debugPrint('AppUpdateService: $e'));
  }

  /// Installs the downloaded update. Call only after the user confirmed: the
  /// app closes (and, where the platform allows, relaunches).
  Future<void> installAndRestart() async {
    final distribution = _resolvedDistribution;
    if (_phase != AppUpdatePhase.readyToInstall || distribution == null) {
      return;
    }
    _setPhase(AppUpdatePhase.installing);
    try {
      switch (distribution) {
        case AppDistribution.windowsInstaller:
        case AppDistribution.windowsPortable:
        case AppDistribution.macosDmg:
          await DesktopUpdateInstaller.launch(
            distribution: distribution,
            packagePath: _packagePath!,
          );
          await _quitApp();
        case AppDistribution.microsoftStore:
          // Windows closes the app while the package is installed.
          final state = await _storeChannel.invokeMethod<String>('install');
          if (state == 'canceled') {
            _setPhase(AppUpdatePhase.readyToInstall);
          } else if (state != 'completed') {
            _fail(state ?? 'otherError');
          }
        case AppDistribution.googlePlay:
          await play.InAppUpdate.completeFlexibleUpdate();
        case AppDistribution.unsupported:
          break;
      }
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _quitApp() async {
    try {
      await windowManager.destroy();
    } catch (_) {}
    exit(0);
  }

  void _fail(Object error) {
    _error = error is PlatformException
        ? (error.message ?? error.code)
        : error.toString();
    _setPhase(AppUpdatePhase.error);
  }

  void _setPhase(AppUpdatePhase phase) {
    _phase = phase;
    notifyListeners();
  }
}
