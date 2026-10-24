import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/utils/app_logger.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:window_manager/window_manager.dart';

import 'windows_engine_host.dart';
import '../../ui/tab_manager/core/tab_window_transfer.dart';
import 'desktop_window_process_launcher.dart';
import 'window_startup_payload.dart';
import 'windows_native_tab_drag_drop_service.dart';
import '../torrent/torrent_launch_request.dart';
import '../torrent/torrent_service.dart';
import '../torrent/torrent_background_receiver.dart';
import '../../core/service_locator.dart';

/// Size of a window opened for torn-off tabs (the runner creates secondary
/// windows at this size), which the drag preview matches.
const Size kTearOffWindowSize = Size(1200, 800);

/// Where the cursor lands in a torn-off window when the caller does not say:
/// roughly the middle of the first tab.
const Offset kDefaultTabTearOffAnchor = Offset(140.0, 27.0);

/// A spare window loaded with torn-off tabs, still hidden.
class PreparedTabWindow {
  final DesktopWindowInfo window;

  /// Its top-level handle, for the native hand-off on release.
  final int? windowHandle;

  const PreparedTabWindow(this.window, this.windowHandle);
}

class DesktopWindowInfo {
  final String windowId;
  final int port;
  final String title;
  final int tabCount;
  final String role;
  final int? processId;

  const DesktopWindowInfo({
    required this.windowId,
    required this.port,
    required this.title,
    required this.tabCount,
    this.role = 'normal',
    this.processId,
  });

  factory DesktopWindowInfo.fromJson(Map<String, dynamic> json) {
    return DesktopWindowInfo(
      windowId: (json['windowId'] as String?) ?? '',
      port: (json['port'] as int?) ?? 0,
      title: (json['title'] as String?) ?? 'Window',
      tabCount: (json['tabCount'] as int?) ?? 0,
      role: (json['role'] as String?) ?? 'normal',
      processId: json['processId'] as int?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'windowId': windowId,
    'port': port,
    'title': title,
    'tabCount': tabCount,
    'role': role,
    'processId': ?processId,
  };
}

class DesktopWindowingService {
  static const int _defaultRegistryPort = 49490;
  final int _registryPort;
  final bool _allowE2EPeers;

  DesktopWindowingService()
    : _registryPort = _defaultRegistryPort,
      _allowE2EPeers = false,
      torrentService = null,
      torrentNotice = null;

  /// Real peer/registry sockets on a test-owned port, with no spare processes.
  @visibleForTesting
  DesktopWindowingService.forTesting({
    required this._registryPort,
    this.torrentService,
    this.torrentNotice,
    String? windowRole,
  }) : _allowE2EPeers = true {
    if (windowRole != null) _windowRole = windowRole;
  }
  final TorrentService? torrentService;
  final TorrentBackgroundNotice? torrentNotice;
  Future<void> _torrentLaunches = Future<void>.value();
  static const Duration _heartbeatInterval = Duration(seconds: 10);
  static const Duration _registryTtl = Duration(seconds: 30);

  final String _windowId = const Uuid().v4();
  final bool _isSecondaryWindow =
      WindowsEngineHost.environment[WindowStartupPayload
          .envSecondaryWindowKey] ==
      '1';
  String _windowRole =
      (WindowsEngineHost.environment[WindowStartupPayload.envWindowRoleKey] ??
              'normal')
          .trim()
          .isEmpty
      ? 'normal'
      : (WindowsEngineHost.environment[WindowStartupPayload.envWindowRoleKey] ??
            'normal');
  Timer? _spareWarmupTimer;
  bool _spareWarmupInFlight = false;
  int _orphanedSpareBeats = 0;
  bool _closing = false;

  /// Spawning a process while a torn-off window is being dragged makes the
  /// drag stutter, so a used spare is replaced only after this delay.
  static const Duration _spareRewarmDelay = Duration(milliseconds: 1500);
  // A debug engine can take seconds to boot; release ones well under one.
  static const Duration _spareBootTimeout = Duration(seconds: 10);

  ServerSocket? _peerServer;
  int? _peerPort;
  StreamSubscription<Socket>? _peerSub;

  ServerSocket? _registryServer;
  StreamSubscription<Socket>? _registrySub;

  Timer? _heartbeat;
  Timer? _registryCleanupTimer;

  TabManagerBloc? _tabBloc;
  StreamSubscription<TabManagerState>? _tabStateSub;

  String _lastTitle = 'CB File Hub';
  int _lastRegisteredTabCount = -1;
  int? _torrentLaunchPriority;

  String get windowId => _windowId;

  bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> attachTabBloc(TabManagerBloc tabBloc) async {
    if (!isDesktop) return;
    if (_tabBloc == tabBloc && _peerServer != null) return;

    _tabBloc = tabBloc;

    if (Platform.isWindows) {
      WindowsNativeTabDragDropService.initialize(tabBloc);
    }

    // An integration-test executable starts its test entrypoint in every child
    // process too. Pre-warming a spare would recursively rerun the suite, while
    // joining the production registry could target the user's real app window.
    if (const bool.fromEnvironment('CB_E2E') && !_allowE2EPeers) return;

    await _startPeerServerIfNeeded();
    await _ensureRegistryServerOrClient();
    _startHeartbeat();
    _listenToTabUpdates();
    if (Platform.isWindows) {
      WindowsNativeTabDragDropService.onTabWindowMerged = () =>
          unawaited(_closeSelf());
      WindowsNativeTabDragDropService.onTabWindowRevealed = () =>
          unawaited(_finishReveal());
    }
    if (Platform.isWindows &&
        !_allowE2EPeers &&
        !const bool.fromEnvironment('CB_E2E')) {
      WindowsNativeTabDragDropService.onTorrentSources = _openTorrentSources;
      WindowsNativeTabDragDropService.onTorrentNotificationClicked =
          _showTorrentLibrary;
      locator<TorrentService>().addListener(_updateTorrentLaunchRouting);
      _updateTorrentLaunchRouting();
    }

    if (!const bool.fromEnvironment('CB_E2E') &&
        !_allowE2EPeers &&
        Platform.isWindows &&
        !_isSecondaryWindow &&
        _windowRole != 'spare') {
      // Pre-warm as early as possible so "new window" feels instant.
      unawaited(ensureSpareWindow());
      _scheduleSpareWarmup();
    }
  }

  Future<void> dispose() async {
    WindowsNativeTabDragDropService.onTabWindowMerged = null;
    WindowsNativeTabDragDropService.onTabWindowRevealed = null;
    if (_torrentLaunchPriority != null) {
      locator<TorrentService>().removeListener(_updateTorrentLaunchRouting);
      WindowsNativeTabDragDropService.onTorrentSources = null;
      WindowsNativeTabDragDropService.onTorrentNotificationClicked = null;
      await WindowsNativeTabDragDropService.setTorrentLaunchPriority(0);
      _torrentLaunchPriority = null;
    }
    _tabStateSub?.cancel();
    _tabStateSub = null;
    _heartbeat?.cancel();
    _heartbeat = null;

    try {
      await _sendRegistryMessage(<String, dynamic>{
        'type': 'unregister',
        'windowId': _windowId,
      });
    } catch (_) {}

    await _peerSub?.cancel();
    _peerSub = null;
    await _peerServer?.close();
    _peerServer = null;

    await _registrySub?.cancel();
    _registrySub = null;
    await _registryServer?.close();
    _registryServer = null;

    _registryCleanupTimer?.cancel();
    _registryCleanupTimer = null;

    _spareWarmupTimer?.cancel();
    _spareWarmupTimer = null;
  }

  Future<List<DesktopWindowInfo>> listWindows() async {
    if (!isDesktop) return const <DesktopWindowInfo>[];

    final response = await _sendRegistryMessage(<String, dynamic>{
      'type': 'list',
    });
    if (response == null) return const <DesktopWindowInfo>[];

    final windows = response['windows'];
    if (windows is! List) return const <DesktopWindowInfo>[];

    return windows
        .whereType<Map>()
        .map((m) => DesktopWindowInfo.fromJson(Map<String, dynamic>.from(m)))
        .where((w) => w.windowId.isNotEmpty && w.port > 0)
        .toList(growable: false);
  }

  Future<List<DesktopWindowInfo>> listOtherWindows() async {
    final windows = await listWindows();
    return windows
        .where((w) => w.windowId != _windowId && w.role == 'normal')
        .toList(growable: false);
  }

  /// Loads [tabs] into the pre-warmed spare window behind the scenes (shown,
  /// but cloaked), while a tab drag preview is still moving. Returns null when
  /// no spare is free right now.
  Future<PreparedTabWindow?> prepareTearOffWindow(
    List<WindowTabPayload> tabs,
  ) async {
    if (!Platform.isWindows || tabs.isEmpty) return null;
    final spare = await _findSpareWindow();
    if (spare == null) {
      unawaited(ensureSpareWindow());
      return null;
    }
    final response = await _sendPeerMessage(
      port: spare.port,
      message: <String, dynamic>{
        'type': 'prepare_tabs',
        'tabs': tabs.map((t) => t.toJson()).toList(growable: false),
      },
    );
    if (response?['type'] != 'ok') return null;
    final handle = response?['windowHandle'];
    return PreparedTabWindow(spare, handle is int ? handle : null);
  }

  /// Shows a window readied by [prepareTearOffWindow] with its content's
  /// top-left at [clientOrigin] (physical screen pixels), when the native
  /// hand-off did not.
  Future<bool> revealPreparedWindow(
    DesktopWindowInfo window,
    Offset clientOrigin,
  ) async {
    final response = await _sendPeerMessage(
      port: window.port,
      message: <String, dynamic>{
        'type': 'reveal_prepared',
        'x': clientOrigin.dx,
        'y': clientOrigin.dy,
      },
    );
    return response?['type'] == 'ok';
  }

  /// Returns a window readied by [prepareTearOffWindow] to being a spare.
  Future<void> discardPreparedWindow(DesktopWindowInfo window) async {
    await _sendPeerMessage(
      port: window.port,
      message: <String, dynamic>{'type': 'discard_prepared'},
    );
  }

  /// Called before constructing another app shell for a Windows association.
  /// Prefer the engine owner, then the primary shell, then another normal shell.
  Future<bool> openTorrentSourcesInExistingWindow(List<String> sources) async {
    if (sources.isEmpty || !sources.every(TorrentLaunchRequest.isSource)) {
      return false;
    }
    final windows = (await listWindows())
        .where((w) => w.role == 'normal')
        .toList();
    // With one shell there is no owner/primary arbitration to perform.
    for (final preference
        in windows.length == 1 ? ['any'] : ['engine', 'primary', 'any']) {
      for (final window in windows) {
        // The association process was launched by the user's click. Pass its
        // foreground permission to the existing shell before asking it to show.
        if (Platform.isWindows) {
          await WindowsNativeTabDragDropService.allowForegroundWindow(
            pid: window.processId,
          );
        }
        final response = await _sendPeerMessage(
          port: window.port,
          message: {
            'type': 'open_torrent_sources',
            'sources': sources,
            'preference': preference,
          },
        );
        if (response?['type'] == 'ok') return true;
      }
    }
    return false;
  }

  void _updateTorrentLaunchRouting() {
    final priority = _windowRole != 'normal'
        ? 0
        : locator<TorrentService>().ownsEngine
        ? 3
        : _isSecondaryWindow
        ? 1
        : 2;
    if (_torrentLaunchPriority == priority) return;
    _torrentLaunchPriority = priority;
    unawaited(
      WindowsNativeTabDragDropService.setTorrentLaunchPriority(priority),
    );
  }

  void _openTorrentSources(List<String> sources) {
    _torrentLaunches = _torrentLaunches
        .then((_) async {
          final service =
              torrentService ??
              (locator.isRegistered<TorrentService>()
                  ? locator<TorrentService>()
                  : null);
          if (service != null && await service.shouldReceiveInBackground()) {
            final notice = torrentNotice;
            final receiver = notice == null
                ? TorrentBackgroundReceiver(service)
                : TorrentBackgroundReceiver(service, notify: notice);
            for (final source in sources) {
              await receiver.receiveSource(source);
            }
            return;
          }
          _openTorrentSourcesInTabs(sources);
        })
        .catchError((Object e, StackTrace stack) {
          AppLogger.warning(
            'Torrent launch failed',
            error: e,
            stackTrace: stack,
          );
        });
  }

  void _showTorrentLibrary() {
    final bloc = _tabBloc;
    if (bloc == null || bloc.isClosed) return;
    final tab = bloc.state.tabs
        .where((t) => TorrentLaunchRequest.isPath(t.path))
        .firstOrNull;
    bloc.add(tab == null ? AddTab(path: '#torrents') : SwitchToTab(tab.id));
    unawaited(focusTorrentWindow());
  }

  void _openTorrentSourcesInTabs(List<String> sources) {
    final bloc = _tabBloc;
    if (bloc == null || bloc.isClosed) return;
    for (final source in sources) {
      bloc.add(
        AddTab(path: TorrentLaunchRequest.pathFor(source), name: 'Torrent'),
      );
    }
    // Focus APIs can wait on the OS. Queue the tab switch first, and acknowledge
    // receipt independently so a slow focus cannot trigger a duplicate launch.
    unawaited(focusTorrentWindow());
  }

  /// Show the shell before opening a torrent dialog, preserving maximization.
  static Future<void> focusTorrentWindow() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
    if (WindowsEngineHost.isAvailable) {
      await WindowsEngineHost.setRole('normal');
      if (locator.isRegistered<DesktopWindowingService>()) {
        final service = locator<DesktopWindowingService>();
        service._windowRole = 'normal';
        service._closing = false;
        unawaited(service._registerSelf());
      }
    }
    try {
      // window_manager.show restores minimized windows without unmaximizing.
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
    // Also try the native activation path when a window_manager call fails.
    if (Platform.isWindows) {
      await WindowsNativeTabDragDropService.forceActivateWindow();
    }
  }

  /// Opens a window holding [tabs]. With [startDragging] the window follows
  /// the cursor (a tab tear-off) with [dragAnchor], a point of its content in
  /// logical pixels, under the cursor; [sourcePointerPosition] is the cursor in
  /// this window, used only when no pre-warmed window is available.
  Future<bool> openNewWindow({
    List<WindowTabPayload> tabs = const [],
    Offset? sourcePointerPosition,
    Offset dragAnchor = kDefaultTabTearOffAnchor,
    bool startDragging = false,
  }) async {
    if (!isDesktop) return false;

    if (Platform.isWindows) {
      final allowForeground =
          WindowsNativeTabDragDropService.allowForegroundWindow();
      DesktopWindowInfo? spare = await _findSpareWindow();
      if (spare == null) {
        // If the user triggers "new window" very quickly after startup,
        // wait briefly for the pre-warmed spare to come online.
        unawaited(ensureSpareWindow());
        spare = await _waitForSpareWindow(
          timeout: const Duration(milliseconds: 900),
        );
      }
      await allowForeground;
      if (spare != null) {
        // One round trip: the spare takes the tabs before it first shows, so
        // it never flashes empty, and starts following the cursor itself.
        final shown = await requestShowWindow(
          spare,
          consumeSpare: true,
          tabs: tabs,
          dragAnchor: startDragging ? dragAnchor : null,
        );
        if (shown) return true;
        // Spare not ready: fall back to creating a fresh window.
      }
    }

    Offset? initialPosition;
    if (sourcePointerPosition != null) {
      try {
        final sourceWindowPosition = await windowManager.getPosition();
        initialPosition =
            sourceWindowPosition + sourcePointerPosition - dragAnchor;
      } catch (_) {}
    }
    final created = await DesktopWindowProcessLauncher.openWindow(
      tabs: tabs,
      startHidden: false,
      windowRole: 'normal',
      initialPositionX: initialPosition?.dx,
      initialPositionY: initialPosition?.dy,
      startDragging: startDragging,
    );
    _scheduleSpareWarmup(delay: _spareRewarmDelay);
    return created;
  }

  /// Shows [target]. A [dragAnchor] makes it follow the cursor until the mouse
  /// button is released, with that point of its content under the cursor.
  Future<bool> requestShowWindow(
    DesktopWindowInfo target, {
    bool consumeSpare = false,
    Offset? initialPosition,
    List<WindowTabPayload> tabs = const [],
    Offset? dragAnchor,
  }) async {
    if (!isDesktop) return false;
    final response = await _sendPeerMessage(
      port: target.port,
      message: <String, dynamic>{
        'type': 'show_window',
        'consumeSpare': consumeSpare,
        if (initialPosition != null) ...<String, dynamic>{
          'positionX': initialPosition.dx,
          'positionY': initialPosition.dy,
        },
        if (tabs.isNotEmpty)
          'tabs': tabs.map((t) => t.toJson()).toList(growable: false),
        if (dragAnchor != null) ...<String, dynamic>{
          'anchorX': dragAnchor.dx,
          'anchorY': dragAnchor.dy,
        },
      },
    );
    return response != null && response['type'] == 'ok';
  }

  Future<void> ensureSpareWindow() async {
    if (_allowE2EPeers || const bool.fromEnvironment('CB_E2E')) return;
    if (!isDesktop) return;
    if (!Platform.isWindows) return;
    // Only the primary window, or whichever window took over the registry
    // after it closed, keeps a spare, so windows never warm one each.
    if (_isSecondaryWindow && _registryServer == null) return;
    if (_windowRole == 'spare') return;
    if (_spareWarmupInFlight) return;
    _spareWarmupInFlight = true;
    try {
      final existing = await _findSpareWindow();
      if (existing != null) return;
      final launched = await DesktopWindowProcessLauncher.openWindow(
        startHidden: true,
        windowRole: 'spare',
      );
      // The launch returns before the spare's isolate boots and registers.
      // Until it does, another call (the startup timer, a tear-off finding no
      // spare) would start a second and third engine; booting them together
      // stalled every window and the shared database for seconds.
      if (launched) await _waitForSpareWindow(timeout: _spareBootTimeout);
    } finally {
      _spareWarmupInFlight = false;
    }
  }

  Future<DesktopWindowInfo?> _findSpareWindow() async {
    if (!isDesktop) return null;
    final windows = await listWindows();
    for (final w in windows) {
      if (w.windowId == _windowId) continue;
      if (w.role == 'spare') return w;
    }
    return null;
  }

  void _scheduleSpareWarmup({
    Duration delay = const Duration(milliseconds: 200),
  }) {
    if (_spareWarmupTimer != null) return;
    _spareWarmupTimer = Timer(delay, () {
      _spareWarmupTimer = null;
      unawaited(ensureSpareWindow());
    });
  }

  Future<DesktopWindowInfo?> _waitForSpareWindow({
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final spare = await _findSpareWindow();
      if (spare != null) return spare;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return null;
  }

  Future<bool> sendTabsToWindow(
    DesktopWindowInfo target,
    List<WindowTabPayload> tabs,
  ) async {
    if (!isDesktop) return false;
    if (tabs.isEmpty) return true;

    final response = await _sendPeerMessage(
      port: target.port,
      message: <String, dynamic>{
        'type': 'open_tabs',
        'tabs': tabs.map((t) => t.toJson()).toList(growable: false),
        'switchToLast': true,
      },
    );
    return response != null && response['type'] == 'ok';
  }

  Future<List<WindowTabPayload>> requestTabsFromWindow(
    DesktopWindowInfo source,
  ) async {
    if (!isDesktop) return const <WindowTabPayload>[];

    final response = await _sendPeerMessage(
      port: source.port,
      message: <String, dynamic>{'type': 'get_tabs'},
    );
    if (response == null || response['type'] != 'tabs') {
      return const <WindowTabPayload>[];
    }
    final tabs = response['tabs'];
    if (tabs is! List) return const <WindowTabPayload>[];
    return tabs
        .whereType<Map>()
        .map((m) => WindowTabPayload.fromJson(Map<String, dynamic>.from(m)))
        .where((t) => t.path.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<bool> requestCloseWindow(DesktopWindowInfo window) async {
    if (!isDesktop) return false;

    final response = await _sendPeerMessage(
      port: window.port,
      message: <String, dynamic>{'type': 'close_window'},
    );
    return response != null && response['type'] == 'ok';
  }

  Future<void> _startPeerServerIfNeeded() async {
    if (_peerServer != null) return;

    try {
      _peerServer = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        shared: true,
      );
      _peerPort = _peerServer!.port;
      _peerSub = _peerServer!.listen(_handlePeerConnection);
    } catch (e, st) {
      AppLogger.error(
        'Failed to start window peer server.',
        error: e,
        stackTrace: st,
      );
      _peerServer = null;
      _peerPort = null;
    }
  }

  void _handlePeerConnection(Socket socket) {
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) async {
            Map<String, dynamic>? message;
            try {
              final decoded = jsonDecode(line);
              if (decoded is Map) {
                message = Map<String, dynamic>.from(decoded);
              }
            } catch (_) {
              message = null;
            }

            if (message == null) {
              _writeJsonLine(socket, <String, dynamic>{
                'type': 'error',
                'message': 'Invalid message',
              });
              return;
            }

            await _handlePeerMessage(socket, message);
          },
          onDone: () {
            socket.destroy();
          },
          onError: (_) {
            socket.destroy();
          },
        );
  }

  Future<void> _handlePeerMessage(
    Socket socket,
    Map<String, dynamic> message,
  ) async {
    final type = message['type'];
    if (type == 'open_torrent_sources') {
      final sources = (message['sources'] as List?)
          ?.whereType<String>()
          .toList();
      final preference = message['preference'];
      final eligible =
          _windowRole == 'normal' &&
          _tabBloc != null &&
          (preference == 'engine'
              ? locator<TorrentService>().ownsEngine
              : preference == 'primary'
              ? !_isSecondaryWindow
              : true);
      if (!eligible ||
          sources == null ||
          sources.isEmpty ||
          sources.length > 100 ||
          !sources.every(TorrentLaunchRequest.isSource)) {
        _writeJsonLine(socket, {'type': 'unavailable'});
        return;
      }
      _openTorrentSources(sources);
      _writeJsonLine(socket, {'type': 'ok'});
      return;
    }
    if (type == 'ping') {
      _writeJsonLine(socket, <String, dynamic>{'type': 'ok'});
      return;
    }

    if (type == 'show_window') {
      final bool consumeSpare = message['consumeSpare'] == true;
      final positionX = message['positionX'];
      final positionY = message['positionY'];
      final initialPosition = positionX is num && positionY is num
          ? Offset(positionX.toDouble(), positionY.toDouble())
          : null;
      final anchorX = message['anchorX'];
      final anchorY = message['anchorY'];
      final dragAnchor = anchorX is num && anchorY is num
          ? Offset(anchorX.toDouble(), anchorY.toDouble())
          : null;
      final tabs = _decodeTabList(message['tabs']);

      try {
        final bloc = _tabBloc;
        if (tabs.isNotEmpty && bloc != null) {
          WindowsNativeTabDragDropService.addTabs(bloc, tabs);
        }
        if (consumeSpare && _windowRole == 'spare') {
          _windowRole = 'normal';
          if (WindowsEngineHost.isAvailable) {
            await WindowsEngineHost.setRole(_windowRole);
          }
          if (_torrentLaunchPriority != null) _updateTorrentLaunchRouting();
          unawaited(_registerSelf());
        }
        if (isDesktop) {
          // Shown cloaked: a hidden window draws nothing, so revealing it
          // right away showed whatever it last drew (its empty home screen),
          // then the tab half-loaded, while the source window already
          // switched to its next tab.
          final holdHidden = Platform.isWindows && tabs.isNotEmpty;
          if (holdHidden) {
            await WindowsNativeTabDragDropService.holdTabWindowHidden(true);
          }
          if (dragAnchor != null) {
            // Start following the cursor before it appears, so the window
            // shows up under it instead of where the cursor was a moment ago.
            await WindowsNativeTabDragDropService.startTabWindowDrag(
              mergeTabs: tabs,
              anchor: dragAnchor,
            );
          } else if (initialPosition != null) {
            await windowManager.setPosition(initialPosition);
          }
          await windowManager.setSkipTaskbar(false);
          await windowManager.show();
          if (holdHidden) {
            await waitForContentToSettle();
            await WindowsNativeTabDragDropService.holdTabWindowHidden(false);
          }
        }
        // The source closes its tabs on this reply, so it comes only once the
        // tabs are on screen here.
        _writeJsonLine(socket, <String, dynamic>{'type': 'ok'});
        if (isDesktop) unawaited(_activateShownWindow());
      } catch (e, st) {
        AppLogger.warning(
          'Failed to show a detached tab window.',
          error: e,
          stackTrace: st,
        );
        _writeJsonLine(socket, <String, dynamic>{
          'type': 'error',
          'message': 'Failed to show window',
        });
      }
      return;
    }

    if (type == 'prepare_tabs') {
      final tabs = _decodeTabList(message['tabs']);
      final bloc = _tabBloc;
      if (_windowRole != 'spare' ||
          bloc == null ||
          tabs.isEmpty ||
          !Platform.isWindows) {
        _writeJsonLine(socket, <String, dynamic>{'type': 'unavailable'});
        return;
      }
      // Taken: no other tear-off may use this spare meanwhile.
      _windowRole = 'preparing';
      if (WindowsEngineHost.isAvailable) {
        await WindowsEngineHost.setRole(_windowRole);
      }
      unawaited(_registerSelf());
      try {
        WindowsNativeTabDragDropService.addTabs(bloc, tabs);
        // Shown, so it renders the tabs, but cloaked and off the taskbar
        // until revealed. Inactive: the source window is mid-drag.
        await WindowsNativeTabDragDropService.holdTabWindowHidden(true);
        await WindowsNativeTabDragDropService.showWindowInactive();
        // The spare left the taskbar while hidden; showing it adds a button.
        await windowManager.setSkipTaskbar(true);
        _writeJsonLine(socket, <String, dynamic>{
          'type': 'ok',
          'windowHandle':
              ?await WindowsNativeTabDragDropService.topLevelWindowHandle(),
        });
      } catch (e, st) {
        AppLogger.warning(
          'Failed to prepare a tab window.',
          error: e,
          stackTrace: st,
        );
        _writeJsonLine(socket, <String, dynamic>{'type': 'error'});
      }
      return;
    }

    if (type == 'reveal_prepared') {
      final x = message['x'];
      final y = message['y'];
      if (_windowRole != 'preparing' || x is! num || y is! num) {
        _writeJsonLine(socket, <String, dynamic>{'type': 'unavailable'});
        return;
      }
      try {
        // The tabs loaded while the preview was dragged: appear at once, and
        // let the source drop its preview; the rest follows.
        await WindowsNativeTabDragDropService.placeWindowClientAt(
          Offset(x.toDouble(), y.toDouble()),
        );
        await WindowsNativeTabDragDropService.holdTabWindowHidden(false);
        if (WindowsEngineHost.isAvailable) {
          // The source may close its final tab as soon as it receives this ack.
          await WindowsEngineHost.setRole('normal');
        }
        _writeJsonLine(socket, <String, dynamic>{'type': 'ok'});
        unawaited(_finishReveal());
      } catch (e, st) {
        AppLogger.warning(
          'Failed to reveal a tab window.',
          error: e,
          stackTrace: st,
        );
        _writeJsonLine(socket, <String, dynamic>{'type': 'error'});
      }
      return;
    }

    if (type == 'discard_prepared') {
      if (_windowRole == 'preparing') {
        try {
          _tabBloc?.add(CloseAllTabs());
          await windowManager.hide();
          await WindowsNativeTabDragDropService.holdTabWindowHidden(false);
        } catch (_) {}
        _windowRole = 'spare';
        if (WindowsEngineHost.isAvailable) {
          await WindowsEngineHost.setRole(_windowRole);
        }
        unawaited(_registerSelf());
      }
      _writeJsonLine(socket, <String, dynamic>{'type': 'ok'});
      return;
    }

    if (type == 'get_tabs') {
      final bloc = _tabBloc;
      final state = bloc?.state;
      final tabs = state?.tabs ?? const [];
      final activeId = state?.activeTabId;
      final activeIndex = activeId == null
          ? null
          : tabs.indexWhere((t) => t.id == activeId);
      _writeJsonLine(socket, <String, dynamic>{
        'type': 'tabs',
        'activeIndex': (activeIndex != null && activeIndex >= 0)
            ? activeIndex
            : null,
        'tabs': tabs
            .map((t) => TabWindowTransfer.capture(t).toJson())
            .toList(growable: false),
      });
      return;
    }

    if (type == 'open_tabs') {
      final bloc = _tabBloc;
      final dynamic tabsValue = message['tabs'];
      final bool switchToLast = message['switchToLast'] == true;
      if (bloc == null || tabsValue is! List) {
        _writeJsonLine(socket, <String, dynamic>{
          'type': 'error',
          'message': 'Tab manager not available',
        });
        return;
      }

      final payloads = _decodeTabList(tabsValue);

      for (int i = 0; i < payloads.length; i++) {
        final p = payloads[i];
        final shouldSwitch = switchToLast ? i == payloads.length - 1 : i == 0;
        bloc.add(
          AddTab(
            path: p.path,
            name: p.name,
            switchToTab: shouldSwitch,
            highlightedFileName: p.highlightedFileName,
            windowPayload: p,
          ),
        );
      }

      _writeJsonLine(socket, <String, dynamic>{'type': 'ok'});
      return;
    }

    if (type == 'close_window') {
      _writeJsonLine(socket, <String, dynamic>{'type': 'ok'});
      Future<void>.delayed(
        const Duration(milliseconds: 50),
        () => unawaited(_closeSelf()),
      );
      return;
    }

    _writeJsonLine(socket, <String, dynamic>{
      'type': 'error',
      'message': 'Not implemented',
    });
  }

  static List<WindowTabPayload> _decodeTabList(Object? value) {
    if (value is! List) return const <WindowTabPayload>[];
    return value
        .whereType<Map>()
        .map((m) => WindowTabPayload.fromJson(Map<String, dynamic>.from(m)))
        .where((t) => t.path.trim().isNotEmpty)
        .toList(growable: false);
  }

  /// Waits until freshly added tabs have loaded and drawn: no frame pending
  /// for two checks in a row. Bounded, since spinners or thumbnails can keep
  /// frames coming.
  @visibleForTesting
  static Future<void> waitForContentToSettle({
    Duration limit = const Duration(milliseconds: 300),
  }) async {
    final binding = SchedulerBinding.instance;
    final elapsed = Stopwatch()..start();
    await Future<void>.delayed(Duration.zero);
    try {
      await binding.endOfFrame.timeout(limit);
    } catch (_) {}
    var quietChecks = 0;
    while (elapsed.elapsed < limit) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      final idle =
          !binding.hasScheduledFrame &&
          binding.schedulerPhase == SchedulerPhase.idle;
      quietChecks = idle ? quietChecks + 1 : 0;
      if (quietChecks >= 2) return;
    }
  }

  /// A readied window has appeared (natively, or via `reveal_prepared`):
  /// make it an ordinary window.
  Future<void> _finishReveal() async {
    if (_windowRole != 'preparing') return;
    _windowRole = 'normal';
    if (WindowsEngineHost.isAvailable) {
      await WindowsEngineHost.setRole(_windowRole);
    }
    if (_torrentLaunchPriority != null) _updateTorrentLaunchRouting();
    unawaited(_registerSelf());
    try {
      await windowManager.setSkipTaskbar(false);
    } catch (_) {}
    await _activateShownWindow();
  }

  static Future<void> _activateShownWindow() async {
    try {
      await windowManager.focus();
    } catch (_) {}
    await WindowsNativeTabDragDropService.forceActivateWindow();
  }

  /// Closes this window, unregistering first so window pickers elsewhere never
  /// list it while it shuts down.
  Future<void> _closeSelf() async {
    if (_closing) return;
    _closing = true;
    if (WindowsEngineHost.isAvailable) {
      await prepareForEngineClose();
      await WindowsEngineHost.close();
      return;
    }
    _heartbeat?.cancel();
    _heartbeat = null;
    await _sendRegistryMessage(<String, dynamic>{
      'type': 'unregister',
      'windowId': _windowId,
    });
    try {
      if (isDesktop) {
        await windowManager.close();
        return;
      }
    } catch (_) {}
    await WindowsEngineHost.closeOrExit();
  }

  /// A retained engine still serves IPC/tasks, but is no longer a tab target.
  Future<void> prepareForEngineClose() async {
    _windowRole = 'background';
    await WindowsEngineHost.setRole('background');
    if (_torrentLaunchPriority != null) _updateTorrentLaunchRouting();
    await _registerSelf();
  }

  void _writeJsonLine(Socket socket, Map<String, dynamic> message) {
    try {
      socket.write('${jsonEncode(message)}\n');
    } catch (_) {}
  }

  Future<void> _ensureRegistryServerOrClient() async {
    if (!isDesktop) return;

    final canConnect = await _canConnectToRegistry();
    if (canConnect) return;

    await _tryStartRegistryServer();
  }

  Future<bool> _canConnectToRegistry() async {
    try {
      final s = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _registryPort,
        timeout: const Duration(milliseconds: 250),
      );
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _tryStartRegistryServer() async {
    if (_registryServer != null) return;
    try {
      _registryServer = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        _registryPort,
        shared: true,
      );
      _registrySub = _registryServer!.listen(_handleRegistryConnection);
      _registryCleanupTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        _cleanupRegistry();
      });
    } catch (_) {
      _registryServer = null;
      _registrySub = null;
    }
  }

  final Map<String, _RegistryEntry> _registry = <String, _RegistryEntry>{};

  void _handleRegistryConnection(Socket socket) {
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            Map<String, dynamic>? message;
            try {
              final decoded = jsonDecode(line);
              if (decoded is Map) {
                message = Map<String, dynamic>.from(decoded);
              }
            } catch (_) {
              message = null;
            }

            if (message == null) {
              _writeJsonLine(socket, <String, dynamic>{
                'type': 'error',
                'message': 'Invalid message',
              });
              return;
            }

            _handleRegistryMessage(socket, message);
          },
          onDone: () {
            socket.destroy();
          },
          onError: (_) {
            socket.destroy();
          },
        );
  }

  void _handleRegistryMessage(Socket socket, Map<String, dynamic> message) {
    final type = message['type'];
    if (type == 'register') {
      final windowId = (message['windowId'] as String?) ?? '';
      final port = (message['port'] as int?) ?? 0;
      final title = (message['title'] as String?) ?? 'Window';
      final tabCount = (message['tabCount'] as int?) ?? 0;
      final role = (message['role'] as String?) ?? 'normal';
      if (windowId.isEmpty || port <= 0) {
        _writeJsonLine(socket, <String, dynamic>{
          'type': 'error',
          'message': 'Invalid registration',
        });
        return;
      }

      final previousRole = _registry[windowId]?.info.role;
      if ((previousRole == 'spare' || previousRole == 'preparing') &&
          role == 'normal') {
        // A spare was just put to use; warm the next one.
        _scheduleSpareWarmup(delay: _spareRewarmDelay);
      }
      _registry[windowId] = _RegistryEntry(
        info: DesktopWindowInfo(
          windowId: windowId,
          port: port,
          title: title,
          tabCount: tabCount,
          role: role,
          processId: message['processId'] as int?,
        ),
        lastSeen: DateTime.now(),
      );

      _writeJsonLine(socket, <String, dynamic>{'type': 'ok'});
      return;
    }

    if (type == 'unregister') {
      final windowId = (message['windowId'] as String?) ?? '';
      if (windowId.isNotEmpty) {
        _registry.remove(windowId);
      }
      _writeJsonLine(socket, <String, dynamic>{'type': 'ok'});
      return;
    }

    if (type == 'list') {
      _cleanupRegistry();
      _writeJsonLine(socket, <String, dynamic>{
        'type': 'list_response',
        'windows': _registry.values
            .map((e) => e.info.toJson())
            .toList(growable: false),
      });
      return;
    }

    _writeJsonLine(socket, <String, dynamic>{
      'type': 'error',
      'message': 'Not implemented',
    });
  }

  void _cleanupRegistry() {
    final cutoff = DateTime.now().subtract(_registryTtl);
    final stale = _registry.entries
        .where((e) => e.value.lastSeen.isBefore(cutoff))
        .map((e) => e.key)
        .toList(growable: false);
    for (final id in stale) {
      _registry.remove(id);
    }
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) async {
      await _registerSelf();
      if (_windowRole == 'spare') await _exitIfOrphanedSpare();
    });
    unawaited(_registerSelf());
  }

  /// A hidden spare outliving every visible window would never be used; quit
  /// once no normal window has been registered for two heartbeats.
  Future<void> _exitIfOrphanedSpare() async {
    final windows = await listWindows();
    if (windows.any((w) => w.role == 'normal')) {
      _orphanedSpareBeats = 0;
      return;
    }
    if (++_orphanedSpareBeats < 2 || _windowRole != 'spare') return;
    await _closeSelf();
  }

  void _listenToTabUpdates() {
    _tabStateSub?.cancel();
    final bloc = _tabBloc;
    if (bloc == null) return;
    _tabStateSub = bloc.stream.listen((state) {
      final name = state.activeTab?.name.trim();
      final title = (name == null || name.isEmpty) ? 'CB File Hub' : name;
      final tabCount = state.tabs.length;
      if (WindowsEngineHost.isAvailable &&
          _windowRole == 'normal' &&
          tabCount == 0 &&
          _lastRegisteredTabCount > 0) {
        unawaited(_closeSelf());
        return;
      }
      // Reorders, drags and loading flags emit too; only what other windows
      // and the title bar show is worth a native call and a registry trip.
      if (title == _lastTitle && tabCount == _lastRegisteredTabCount) return;
      final titleChanged = title != _lastTitle;
      _lastTitle = title;
      _lastRegisteredTabCount = tabCount;
      if (titleChanged) unawaited(_updateWindowTitle());
      unawaited(_registerSelf());
    });
  }

  Future<void> _updateWindowTitle() async {
    if (!isDesktop) return;
    try {
      await windowManager.setTitle('CB File Hub - $_lastTitle');
    } catch (_) {}
  }

  Future<void> _registerSelf() async {
    if (!isDesktop) return;
    if (_peerPort == null) return;

    await _ensureRegistryServerOrClient();

    await _sendRegistryMessage(<String, dynamic>{
      'type': 'register',
      'windowId': _windowId,
      'port': _peerPort,
      'title': _lastTitle,
      'tabCount': _tabBloc?.state.tabs.length ?? 0,
      'role': _windowRole,
      'processId': pid,
    });
  }

  Future<Map<String, dynamic>?> _sendRegistryMessage(
    Map<String, dynamic> message,
  ) async {
    if (!isDesktop) return null;

    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _registryPort,
        timeout: const Duration(seconds: 1),
      );
      socket.write('${jsonEncode(message)}\n');
      await socket.flush();

      final line = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 1));
      socket.destroy();

      final decoded = jsonDecode(line);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _sendPeerMessage({
    required int port,
    required Map<String, dynamic> message,
  }) async {
    if (!isDesktop) return null;

    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(seconds: 1),
      );
      socket.write('${jsonEncode(message)}\n');
      await socket.flush();

      final line = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 2));
      socket.destroy();

      final decoded = jsonDecode(line);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }
}

class _RegistryEntry {
  final DesktopWindowInfo info;
  final DateTime lastSeen;

  const _RegistryEntry({required this.info, required this.lastSeen});
}
