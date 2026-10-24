import 'dart:io';

import 'package:cb_file_manager/services/media/media_kit_playback.dart';
import 'package:cb_file_manager/services/windowing/desktop_window_process_launcher.dart';
import 'package:cb_file_manager/services/windowing/windows_engine_host.dart';
import 'package:cb_file_manager/services/windowing/window_startup_payload.dart';
import 'package:cb_file_manager/services/windowing/video_window_service.dart';
import 'package:cb_file_manager/services/pip_window_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

class _RecordingPlayer extends mk.PlatformPlayer {
  _RecordingPlayer(this.log)
    : super(configuration: const mk.PlayerConfiguration());
  final List<String> log;

  @override
  Future<void> dispose({bool synchronized = true}) async {
    log.add('dispose');
    await super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  var primary = false;
  var failCreate = false;

  setUp(() {
    calls.clear();
    primary = false;
    failCreate = false;
    messenger.setMockMethodCallHandler(WindowsEngineHost.channel, (call) async {
      calls.add(call);
      if (call.method == 'startup') {
        return {
          'primary': primary,
          'engineId': primary ? 'primary' : '4',
          'environment': {
            'CB_SECONDARY_WINDOW': '1',
            'CB_WINDOW_ROLE': 'normal',
            'CB_PIP_MODE': '1',
            'CB_VIDEO_WINDOW': '1',
            'CB_STARTUP_TABS': 'stale tabs',
          },
        };
      }
      if (call.method == 'create') {
        if (failCreate) throw PlatformException(code: 'engine-create-failed');
        return true;
      }
      return null;
    });
  });
  tearDown(() {
    WindowsEngineHost.resetForTesting();
    VideoWindowService.resetForTesting();
    messenger.setMockMethodCallHandler(WindowsEngineHost.channel, null);
  });

  test('secondary startup is local to this engine', () async {
    await WindowsEngineHost.initializeForTesting();
    expect(WindowsEngineHost.isAvailable, isTrue);
    expect(WindowsEngineHost.isPrimary, isFalse);
    expect(WindowsEngineHost.engineId, '4');
    expect(WindowsEngineHost.environment['CB_SECONDARY_WINDOW'], '1');
    expect(WindowsEngineHost.environment['CB_WINDOW_ROLE'], 'normal');
    expect(
      WindowsEngineHost.environment.entries
          .where((e) => e.key.toUpperCase() == 'PATH')
          .single
          .value,
      isNotEmpty,
    );
  });

  test(
    'tab and progress launchers ask the existing host for new engines',
    () async {
      await WindowsEngineHost.initializeForTesting();
      expect(
        await DesktopWindowProcessLauncher.openWindow(
          tabs: const [WindowTabPayload(path: r'C:\Music')],
          startHidden: true,
          windowRole: 'spare',
        ),
        isTrue,
      );
      expect(
        await DesktopWindowProcessLauncher.openProgressWindow(
          ipcPort: 12345,
          title: 'Copy',
          total: 12,
        ),
        isTrue,
      );
      final launches = calls.where((c) => c.method == 'create').toList();
      expect(launches, hasLength(2));
      final spare = (launches.first.arguments as Map)['environment'] as Map;
      expect(spare['CB_WINDOW_ROLE'], 'spare');
      expect(spare['CB_START_HIDDEN'], '1');
      expect(spare['CB_STARTUP_TABS'], contains(r'C:\\Music'));
      expect(spare.containsKey('CB_PIP_MODE'), isFalse);
      expect(spare.containsKey('CB_VIDEO_WINDOW'), isFalse);
      expect(
        spare.keys.every((key) => (key as String).startsWith('CB_')),
        isTrue,
      );
      final progress = (launches.last.arguments as Map)['environment'] as Map;
      expect(progress['CB_WINDOW_ROLE'], 'progress');
      expect(progress['CB_PROGRESS_IPC_PORT'], '12345');
      expect(progress['CB_PROGRESS_TOTAL'], '12');
      expect(progress.containsKey('CB_STARTUP_TABS'), isFalse);
    },
    skip: !Platform.isWindows,
  );

  test(
    'failed engine creation is reported without spawning a process',
    () async {
      await WindowsEngineHost.initializeForTesting();
      failCreate = true;
      expect(await DesktopWindowProcessLauncher.openWindow(), isFalse);
      expect(calls.where((c) => c.method == 'create'), hasLength(1));
    },
    skip: !Platform.isWindows,
  );

  test(
    'video and PiP also create engines in the existing Windows host',
    () async {
      await WindowsEngineHost.initializeForTesting();
      VideoWindowService.reuseRequesterForTesting = (_) async => false;
      expect(
        await VideoWindowService.openVideoWindow(r'C:\Videos\one.mp4'),
        isTrue,
      );
      expect(
        await PipWindowService.openDesktopPipWindow({
          'path': r'C:\Videos\one.mp4',
        }),
        isTrue,
      );
      final launches = calls.where((c) => c.method == 'create').toList();
      final video = (launches.first.arguments as Map)['environment'] as Map;
      final pip = (launches.last.arguments as Map)['environment'] as Map;
      expect(video['CB_WINDOW_ROLE'], 'video');
      expect(video.containsKey('CB_PIP_MODE'), isFalse);
      expect(video.containsKey('CB_STARTUP_TABS'), isFalse);
      expect(pip['CB_WINDOW_ROLE'], 'pip');
      expect(pip['CB_PIP_MODE'], '1');
      expect(pip.containsKey('CB_VIDEO_WINDOW'), isFalse);
    },
    skip: !Platform.isWindows,
  );

  test(
    'busy reasons are independent and native close requests stay in host',
    () async {
      await WindowsEngineHost.initializeForTesting();
      await WindowsEngineHost.retainWhileBusy('copy', true);
      await WindowsEngineHost.retainWhileBusy(
        'torrent',
        true,
        keepsProcess: false,
      );
      await WindowsEngineHost.retainWhileBusy('copy', true);
      await WindowsEngineHost.retainWhileBusy('copy', false);
      final retention = calls.where((c) => c.method == 'retain').toList();
      expect(retention.map((c) => c.arguments), [
        {'reason': 'copy', 'busy': true, 'keepsProcess': true},
        {'reason': 'torrent', 'busy': true, 'keepsProcess': false},
        {'reason': 'copy', 'busy': false, 'keepsProcess': true},
      ]);
      await messenger.handlePlatformMessage(
        WindowsEngineHost.channel.name,
        WindowsEngineHost.channel.codec.encodeMethodCall(
          const MethodCall('closeRequested'),
        ),
        (_) {},
      );
      expect(calls.last.method, 'close');
    },
  );

  group('media is released before the engine is destroyed', () {
    late List<String> log;
    late PlaybackPlayer player;

    setUp(() {
      log = [];
      player = PlaybackPlayer(
        player: mk.Player(platformPlayer: _RecordingPlayer(log)),
      );
      messenger.setMockMethodCallHandler(WindowsEngineHost.channel, (
        call,
      ) async {
        log.add(call.method);
        if (call.method == 'startup') {
          return {'primary': primary, 'engineId': '4', 'environment': {}};
        }
        return null;
      });
    });
    tearDown(() => player.dispose());

    test('a secondary engine disposes players before closing', () async {
      await WindowsEngineHost.initializeForTesting();
      await WindowsEngineHost.close();
      expect(log, ['startup', 'dispose', 'close']);
    });

    test('a hidden engine keeps them until its last retain ends', () async {
      await WindowsEngineHost.initializeForTesting();
      await WindowsEngineHost.retainWhileBusy('copy', true);
      await WindowsEngineHost.close();
      expect(log, ['startup', 'retain', 'close']);
      await WindowsEngineHost.retainWhileBusy('copy', false);
      expect(log, ['startup', 'retain', 'close', 'dispose', 'retain']);
    });

    test('the primary only releases them when the host quits', () async {
      primary = true;
      await WindowsEngineHost.initializeForTesting();
      await WindowsEngineHost.close();
      expect(log, ['startup', 'close']);
      await messenger.handlePlatformMessage(
        WindowsEngineHost.channel.name,
        WindowsEngineHost.channel.codec.encodeMethodCall(
          const MethodCall('releaseMedia'),
        ),
        (_) {},
      );
      expect(log, ['startup', 'close', 'dispose']);
    });
  });

  test('a failing close handler still closes the window', () async {
    await WindowsEngineHost.initializeForTesting();
    WindowsEngineHost.onCloseRequested = () async =>
        throw StateError('registry unreachable');
    await messenger.handlePlatformMessage(
      WindowsEngineHost.channel.name,
      WindowsEngineHost.channel.codec.encodeMethodCall(
        const MethodCall('closeRequested'),
      ),
      (_) {},
    );
    expect(calls.last.method, 'close');
  });
}
