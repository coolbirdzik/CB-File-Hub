import 'package:cb_file_manager/services/windowing/windows_engine_host.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import '../../../config/languages/app_localizations_delegate.dart';
import '../../../design_system/cb_design_system.dart';
import '../../../services/windowing/torrent_options_window_service.dart';
import '../../../services/windowing/torrent_options_window_anchor.dart';
import 'torrent_download_dialog.dart';

/// Short startup path: no app shell, service locator, database, or aria2.
Future<void> runTorrentOptionsWindow(Map<String, String> env) async {
  final port = int.tryParse(env[TorrentOptionsWindowService.envPort] ?? '');
  final token = env[TorrentOptionsWindowService.envToken];
  if (port == null || port <= 0 || token == null || token.isEmpty) {
    await WindowsEngineHost.closeOrExit(1);
    return;
  }
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(720, 420),
      minimumSize: Size(540, 360),
      title: 'CB File Hub',
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      skipTaskbar: true,
      alwaysOnTop: false,
    ),
  );
  await windowManager.setPreventClose(true);
  await windowManager.setMaximizable(false);
  await windowManager.hide();
  runApp(TorrentOptionsWindowApp(port: port, token: token));
}

class TorrentOptionsWindowApp extends StatefulWidget {
  final int port;
  final String token;

  const TorrentOptionsWindowApp({
    super.key,
    required this.port,
    required this.token,
  });

  @override
  State<TorrentOptionsWindowApp> createState() =>
      _TorrentOptionsWindowAppState();
}

class _TorrentOptionsWindowAppState extends State<TorrentOptionsWindowApp>
    with WindowListener {
  Socket? _socket;
  StreamSubscription<String>? _messages;
  TorrentDownloadRequest? _request;
  int? _id;
  bool _finishing = false;
  bool _destroying = false;
  bool _minimized = false;
  Completer<void>? _painted;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_connect()));
  }

  Future<void> _connect() async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        widget.port,
        timeout: const Duration(seconds: 5),
      );
      _socket = socket;
      _messages = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) => unawaited(_open(line)),
            onDone: _destroy,
            onError: (_) => _destroy(),
          );
      socket.write('${jsonEncode({'token': widget.token, 'pid': pid})}\n');
    } catch (_) {
      await _destroy();
    }
  }

  Future<void> _open(String line) async {
    try {
      if (line.length > 65536 || _request != null) {
        throw const FormatException('Invalid torrent options request');
      }
      final message = jsonDecode(line) as Map<String, dynamic>;
      final request = TorrentDownloadRequest.fromJson(
        Map<String, dynamic>.from(message['request'] as Map),
      );
      final anchor = TorrentOptionsWindowAnchor.fromJson(
        Map<String, dynamic>.from(message['anchor'] as Map? ?? const {}),
      );
      if (_minimized) await windowManager.restore();
      await anchor.place();
      if (!mounted) return;
      final painted = _painted = Completer<void>();
      setState(() {
        _id = message['id'] as int;
        _request = request;
      });
      // Paint the actual form before exposing the native window.
      await painted.future;
      if (_destroying || !mounted || _request != request) return;
      await windowManager.setTitle('${request.name} — CB File Hub');
      await windowManager.setSkipTaskbar(false);
      await windowManager.show();
      // Show already activates the HWND on Windows. Avoid two extra native
      // activation round trips for every request.
      if (!Platform.isWindows) await windowManager.focus();
    } catch (e) {
      _socket?.write('${jsonEncode({'id': _id, 'error': '$e'})}\n');
      await _destroy();
    }
  }

  @override
  void onWindowClose() => unawaited(_finish(null));

  @override
  void onWindowMinimize() => _minimized = true;

  @override
  void onWindowRestore() => _minimized = false;

  Future<void> _finish(TorrentDownloadOptions? options) async {
    if (_request == null || _finishing || _destroying) return;
    _finishing = true;
    try {
      // Hide first so the next queued request cannot be hidden by this one.
      await windowManager.hide();
      await windowManager.setSkipTaskbar(true);
      final id = _id;
      if (mounted) setState(() => _request = null);
      _socket?.write(
        '${jsonEncode({'id': id, 'options': options?.toJson()})}\n',
      );
      await _socket?.flush();
    } catch (_) {
      await _destroy();
    } finally {
      _finishing = false;
    }
  }

  Future<void> _destroy() async {
    if (_destroying) return;
    _destroying = true;
    if (_painted?.isCompleted == false) _painted!.complete();
    _socket?.destroy();
    // windowManager.destroy posts WM_QUIT, which now ends every window.
    if (WindowsEngineHost.isAvailable) {
      await WindowsEngineHost.close();
    } else {
      await windowManager.destroy();
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    unawaited(_messages?.cancel());
    _socket?.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TorrentOptionsWindowContent(
      request: _request,
      requestId: _id,
      onComplete: (options) => unawaited(_finish(options)),
      onWindowDrag: () => unawaited(windowManager.startDragging()),
      onWindowMinimize: () => unawaited(windowManager.minimize()),
      onReady: () {
        if (_painted?.isCompleted == false) _painted!.complete();
      },
    );
  }
}

/// Keeps appearance loaded while the reusable native window is hidden.
class TorrentOptionsWindowContent extends StatefulWidget {
  final TorrentDownloadRequest? request;
  final int? requestId;
  final ValueChanged<TorrentDownloadOptions?> onComplete;
  final VoidCallback onReady;
  final VoidCallback? onWindowDrag;
  final VoidCallback? onWindowMinimize;

  const TorrentOptionsWindowContent({
    super.key,
    required this.request,
    required this.requestId,
    required this.onComplete,
    required this.onReady,
    this.onWindowDrag,
    this.onWindowMinimize,
  });

  @override
  State<TorrentOptionsWindowContent> createState() =>
      _TorrentOptionsWindowContentState();
}

class _TorrentOptionsWindowContentState
    extends State<TorrentOptionsWindowContent> {
  ThemeData? _theme;
  bool _dark = false;
  int _accent = 0xFF0078D4;
  String _language = 'en';

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    if (request != null) {
      if (_dark != request.dark || _accent != request.accent) _theme = null;
      _dark = request.dark;
      _accent = request.accent;
      _language = request.language;
    }
    _theme ??= CbThemeBuilder.build(
      brightness: _dark ? Brightness.dark : Brightness.light,
      accent: Color(_accent),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme,
      themeAnimationDuration: Duration.zero,
      locale: Locale(_language),
      supportedLocales: const [
        Locale('en'),
        Locale('vi'),
        Locale('tr'),
        Locale('zh'),
      ],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: request == null
          ? const SizedBox.shrink()
          : TorrentDownloadDialog(
              key: ValueKey(widget.requestId),
              name: request.name,
              initialDestination: request.initialDestination,
              startImmediately: request.startImmediately,
              destinationLocked: request.destinationLocked,
              onComplete: widget.onComplete,
              onReady: widget.onReady,
              onWindowDrag: widget.onWindowDrag,
              onWindowMinimize: widget.onWindowMinimize,
            ),
    );
  }
}
