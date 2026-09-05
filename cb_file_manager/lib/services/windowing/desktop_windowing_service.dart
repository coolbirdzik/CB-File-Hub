import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/utils/app_logger.dart';
import 'package:uuid/uuid.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_window_process_launcher.dart';
import 'window_startup_payload.dart';
import 'windows_native_tab_drag_drop_service.dart';

const double kDefaultTabTearOffAnchorX = 140.0;
const double kDefaultTabTearOffAnchorY = 18.0;
const Duration kDefaultTabTearOffDragDelay = Duration(milliseconds: 16);

class DesktopWindowInfo {
  final String windowId;
  final int port;
  final String title;
  final int tabCount;
  final String role;

  const DesktopWindowInfo({
    required this.windowId,
    required this.port,
    required this.title,
    required this.tabCount,
    this.role = 'normal',
  });

  factory DesktopWindowInfo.fromJson(Map<String, dynamic> json) {
    return DesktopWindowInfo(
      windowId: (json['windowId'] as String?) ?? '',
      port: (json['port'] as int?) ?? 0,
      title: (json['title'] as String?) ?? 'Window',
      tabCount: (json['tabCount'] as int?) ?? 0,
      role: (json['role'] as String?) ?? 'normal',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'windowId': windowId,
    'port': port,
    'title': title,
    'tabCount': tabCount,
    'role': role,
  };
}

class DesktopWindowingService {
  static const int _registryPort = 49490;
  static const Duration _heartbeatInterval = Duration(seconds: 10);
  static const Duration _registryTtl = Duration(seconds: 30);

  final String _windowId = const Uuid().v4();
  final bool _isSecondaryWindow =
      Platform.environment[WindowStartupPayload.envSecondaryWindowKey] == '1';
  String _windowRole =
      (Platform.environment[WindowStartupPayload.envWindowRoleKey] ?? 'normal')
          .trim()
          .isEmpty
      ? 'normal'
      : (Platform.environment[WindowStartupPayload.envWindowRoleKey] ??
            'normal');
  Timer? _spareWarmupTimer;
  bool _spareWarmupInFlight = false;

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

    await _startPeerServerIfNeeded();
    await _ensureRegistryServerOrClient();
    _startHeartbeat();
    _listenToTabUpdates();

    if (Platform.isWindows && !_isSecondaryWindow && _windowRole != 'spare') {
      // Pre-warm as early as possible so "new window" feels instant.
      unawaited(ensureSpareWindow());
      _scheduleSpareWarmup();
    }
  }

  Future<void> dispose() async {
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
        .where((w) => w.windowId != _windowId && w.role != 'spare')
        .toList(growable: false);
  }

  Future<bool> openNewWindow({
    List<WindowTabPayload> tabs = const [],
    Offset? sourcePointerPosition,
    bool startDragging = false,
  }) async {
    if (!isDesktop) return false;

    Offset? initialPosition;
    if (sourcePointerPosition != null) {
      try {
        final sourceWindowPosition = await windowManager.getPosition();
        initialPosition = Offset(
          sourceWindowPosition.dx +
              sourcePointerPosition.dx -
              kDefaultTabTearOffAnchorX,
          sourceWindowPosition.dy +
              sourcePointerPosition.dy -
              kDefaultTabTearOffAnchorY,
        );
      } catch (_) {}
    }

    if (Platform.isWindows) {
      await WindowsNativeTabDragDropService.allowForegroundWindow();
      DesktopWindowInfo? spare = await _findSpareWindow();
      if (spare == null) {
        // If the user triggers "new window" very quickly after startup,
        // wait briefly for the pre-warmed spare to come online.
        unawaited(ensureSpareWindow());
        spare = await _waitForSpareWindow(
          timeout: const Duration(milliseconds: 900),
        );
      }
      if (spare != null) {
        final shown = await requestShowWindow(
          spare,
          consumeSpare: true,
          initialPosition: initialPosition,
          startDragging: startDragging,
        );
        if (shown) {
          if (tabs.isNotEmpty) {
            // Make the window appear immediately, then stream tabs in.
            // This feels closer to Chrome where the window shows first.
            final delivered = await sendTabsToWindow(spare, tabs);
            unawaited(ensureSpareWindow());
            return delivered;
          }
          unawaited(ensureSpareWindow());
          return true;
        }
        // Spare not ready: fall back to creating a fresh window.
      }
    }

    final created = await DesktopWindowProcessLauncher.openWindow(
      tabs: tabs,
      startHidden: false,
      windowRole: 'normal',
      initialPositionX: initialPosition?.dx,
      initialPositionY: initialPosition?.dy,
      startDragging: startDragging,
    );
    unawaited(ensureSpareWindow());
    return created;
  }

  Future<bool> requestShowWindow(
    DesktopWindowInfo target, {
    bool consumeSpare = false,
    Offset? initialPosition,
    bool startDragging = false,
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
        'startDragging': startDragging,
      },
    );
    return response != null && response['type'] == 'ok';
  }

  Future<void> ensureSpareWindow() async {
    if (!isDesktop) return;
    if (!Platform.isWindows) return;
    if (_isSecondaryWindow) return;
    if (_windowRole == 'spare') return;
    if (_spareWarmupInFlight) return;
    _spareWarmupInFlight = true;
    try {
      final existing = await _findSpareWindow();
      if (existing != null) return;
      await DesktopWindowProcessLauncher.openWindow(
        startHidden: true,
        windowRole: 'spare',
      );
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

  void _scheduleSpareWarmup() {
    if (_spareWarmupTimer != null) return;
    _spareWarmupTimer = Timer(const Duration(milliseconds: 200), () {
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
    if (type == 'ping') {
      _writeJsonLine(socket, <String, dynamic>{'type': 'ok'});
      return;
    }

    if (type == 'show_window') {
      final bool consumeSpare = message['consumeSpare'] == true;
      final bool startDragging = message['startDragging'] == true;
      final positionX = message['positionX'];
      final positionY = message['positionY'];
      final initialPosition = positionX is num && positionY is num
          ? Offset(positionX.toDouble(), positionY.toDouble())
          : null;

      try {
        if (isDesktop) {
          await windowManager.setSkipTaskbar(false);
          if (initialPosition != null) {
            await windowManager.setPosition(initialPosition);
          }
          await windowManager.show();
          await windowManager.focus();
          await WindowsNativeTabDragDropService.forceActivateWindow();
        }
        if (consumeSpare && _windowRole == 'spare') {
          _windowRole = 'normal';
          unawaited(_registerSelf());
        }
        _writeJsonLine(socket, <String, dynamic>{'type': 'ok'});
        if (startDragging && isDesktop) {
          unawaited(
            Future<void>.delayed(kDefaultTabTearOffDragDelay, () async {
              await WindowsNativeTabDragDropService.startWindowDragIfMouseDown();
            }),
          );
        }
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
            .map(
              (t) => WindowTabPayload(
                path: t.path,
                name: t.name,
                highlightedFileName: t.highlightedFileName,
              ).toJson(),
            )
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

      final payloads = tabsValue
          .whereType<Map>()
          .map((m) => WindowTabPayload.fromJson(Map<String, dynamic>.from(m)))
          .where((t) => t.path.trim().isNotEmpty)
          .toList(growable: false);

      for (int i = 0; i < payloads.length; i++) {
        final p = payloads[i];
        final shouldSwitch = switchToLast ? i == payloads.length - 1 : i == 0;
        bloc.add(
          AddTab(
            path: p.path,
            name: p.name,
            switchToTab: shouldSwitch,
            highlightedFileName: p.highlightedFileName,
          ),
        );
      }

      _writeJsonLine(socket, <String, dynamic>{'type': 'ok'});
      return;
    }

    if (type == 'close_window') {
      _writeJsonLine(socket, <String, dynamic>{'type': 'ok'});
      Future<void>.delayed(const Duration(milliseconds: 50), () async {
        try {
          if (isDesktop) {
            await windowManager.close();
            return;
          }
        } catch (_) {}
        exit(0);
      });
      return;
    }

    _writeJsonLine(socket, <String, dynamic>{
      'type': 'error',
      'message': 'Not implemented',
    });
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

      _registry[windowId] = _RegistryEntry(
        info: DesktopWindowInfo(
          windowId: windowId,
          port: port,
          title: title,
          tabCount: tabCount,
          role: role,
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
    });
    unawaited(_registerSelf());
  }

  void _listenToTabUpdates() {
    _tabStateSub?.cancel();
    final bloc = _tabBloc;
    if (bloc == null) return;
    _tabStateSub = bloc.stream.listen((state) {
      final title = state.activeTab?.name.trim();
      _lastTitle = (title == null || title.isEmpty) ? 'CB File Hub' : title;

      unawaited(_updateWindowTitle());
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
