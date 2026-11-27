import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:cb_file_manager/services/local_ai/local_ai_advisor_service.dart';
import 'package:cb_file_manager/services/local_ai/local_model_downloads.dart';
import 'package:cb_file_manager/services/media/subtitle_batch/subtitle_batch_job_runner.dart';
import 'package:cb_file_manager/services/media/subtitle_batch/subtitle_batch_models.dart';
import 'package:cb_file_manager/services/media/subtitle_batch/subtitle_batch_queue.dart';
import 'package:cb_file_manager/services/media/subtitle_batch/subtitle_batch_store.dart';
import 'package:cb_file_manager/services/media/subtitle_preferences.dart';
import 'package:cb_file_manager/services/media/subtitle_services.dart';
import 'package:cb_file_manager/services/system/system_resources.dart';
import 'package:cb_file_manager/ui/components/common/breadcrumb_address_bar.dart';
import 'package:cb_file_manager/ui/screens/subtitle_queue/subtitle_queue_screen.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/widgets/thumbnail_loader.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'network_browsing/network_recovery_test.dart' show host;

const _settings = SubtitleBatchSettings(
  speechModel: 'whisper/small',
  sourceLanguage: 'auto',
  translationModel: 'tencent/Hy-MT2-1.8B-GGUF',
  targetLanguage: 'vi',
);

class _IdleRunner extends SubtitleBatchJobRunner {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory thumbnailRoot;

  setUpAll(() async {
    thumbnailRoot = await Directory.systemTemp.createTemp('cb_subtitle_grid_');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (_) async => thumbnailRoot.path,
        );
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(128, 72);
    final frame = await File(p.join(thumbnailRoot.path, 'frame.png'))
        .writeAsBytes(
          (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List(),
        );
    image.dispose();
    picture.dispose();
    await File(
      p.join(thumbnailRoot.path, 'thumbnail_cache_index.json'),
    ).writeAsString(
      jsonEncode({
        for (var i = 1; i <= 12; i++)
          VideoThumbnailHelper.getNormalizedPath(
            p.join(r'D:\Videos\Anime', 'Show S01E${'$i'.padLeft(2, '0')}.mkv'),
          ): frame.path,
        for (var i = 1; i <= 2; i++)
          VideoThumbnailHelper.getNormalizedPath(
            p.join(r'D:\Courses', 'Lecture 0$i.mp4'),
          ): frame.path,
      }),
    );
    await VideoThumbnailHelper.initializeCache();
    final inter = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await inter.load();
    await (FontLoader('packages/phosphor_flutter/PhosphorLight')..addFont(
          rootBundle.load(
            'packages/phosphor_flutter/lib/fonts/Phosphor-Light.ttf',
          ),
        ))
        .load();
  });

  tearDownAll(() async {
    await DatabaseManager.getInstance().close();
    await SqliteDatabaseProvider.closeSharedDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await thumbnailRoot.delete(recursive: true);
  });

  Future<void> render(
    WidgetTester tester, {
    required Size size,
    required bool withData,
    String? shot,
    bool vietnamese = false,
    Future<void> Function()? interact,
    Map<String, Object> initialPrefs = const {},
    void Function(SubtitleBatchStore store)? onStore,
  }) async {
    final expectGuide = !withData;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    late Database db;
    late SubtitleBatchStore store;
    late SubtitleBatchQueue queue;
    late SubtitleServices services;
    final tabs = TabManagerBloc();
    addTearDown(tabs.close);
    await tester.runAsync(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      store = SubtitleBatchStore(openDatabase: () async => db);
      onStore?.call(store);
      queue = SubtitleBatchQueue(
        store: store,
        runner: _IdleRunner(),
        playbackActive: () async => false,
        tick: const Duration(hours: 1),
        modelChanges: () async => const Stream.empty(),
        resources: SystemResourceMonitor(
          interval: const Duration(hours: 1),
          sampler: () async => const SystemResourceSample(
            cpu: .37,
            ramTotal: 64 << 30,
            ramAvailable: 11 << 30,
            gpu: .99,
            vramTotal: 16 << 30,
            vramUsed: 14 << 30,
            diskBusy: .57,
            diskName: '6 C: D:',
          ),
        ),
        queueResources: SystemResourceMonitor(
          interval: const Duration(hours: 1),
          sampler: () async => const SystemResourceSample(
            cpu: .12,
            ramTotal: 64 << 30,
            processRamUsed: 3 << 30,
            gpu: .42,
            vramTotal: 16 << 30,
            vramUsed: 5 << 30,
            ioBytesPerSecond: 8388608.0,
          ),
        ),
      );
      SharedPreferences.setMockInitialValues(initialPrefs);
      final prefs = await SharedPreferences.getInstance();
      final models = LocalAiAdvisorService(
        prefs: prefs,
        documentsDirectoryProvider: () async => Directory.systemTemp,
      );
      services = SubtitleServices(
        models,
        LocalModelDownloads(models),
        SubtitlePreferences(prefs),
      );
      if (withData) {
        final anime = await store.saveRule(
          const SubtitleBatchRule(
            name: 'Anime season 1',
            folders: [r'D:\Videos\Anime', r'E:\Downloads\Series'],
            speechModel: 'whisper/small',
            sourceLanguage: 'ja',
            translationModel: 'tencent/Hy-MT2-1.8B-GGUF',
            targetLanguage: 'vi',
          ),
        );
        final lectures = await store.saveRule(
          const SubtitleBatchRule(
            name: 'Lectures',
            enabled: false,
            folders: [r'D:\Courses'],
            speechModel: 'whisper/small',
            sourceLanguage: 'auto',
            translationModel: 'tencent/Hy-MT2-1.8B-GGUF',
            targetLanguage: 'app',
          ),
        );
        await store.enqueue(
          [
            for (var i = 1; i <= 12; i++)
              p.join(
                r'D:\Videos\Anime',
                'Show S01E${'$i'.padLeft(2, '0')}.mkv',
              ),
          ],
          settings: _settings,
          ruleId: anime.id,
          ruleName: 'Anime season 1',
        );
        await store.enqueue(
          [
            p.join(r'D:\Courses', 'Lecture 01.mp4'),
            p.join(r'D:\Courses', 'Lecture 02.mp4'),
          ],
          settings: _settings,
          ruleId: lectures.id,
          ruleName: 'Lectures',
        );
        final running = (await store.claimNext())!;
        await store.reportProgress(running, .42);
        final done = (await store.claimNext())!;
        await store.finish(
          done,
          SubtitleBatchStatus.done,
          progress: 1,
          outputPath: r'D:\Videos\Anime\Subs\Show S01E02.vi.srt',
        );
        final failed = (await store.claimNext())!;
        await store.finish(
          failed,
          SubtitleBatchStatus.failed,
          message: 'Cannot read the video duration',
        );
        await store.requeue(running);
        await store.claimNext();
      }
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('shot'),
        child: host(
          BlocProvider.value(
            value: tabs,
            child: SubtitleQueueScreen(
              tabId: 'queue',
              queue: queue,
              store: store,
              services: () async => services,
            ),
          ),
          vietnamese: vietnamese,
        ),
      ),
    );
    // Loading shows the slim bar along the top, never a spinner. The data
    // needs real async work, so it is still loading after a plain pump.
    await tester.pump();
    expect(find.byType(SubtitleQueueScreen), findsOneWidget);
    expect(
      find.byKey(const ValueKey('subtitle-queue-loading')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('subtitle-queue-loading')),
      findsNothing,
      reason: 'the bar goes away once loaded',
    );
    // Every tab shows the browser address bar.
    expect(find.byType(BreadcrumbAddressBar), findsOneWidget);
    // The toolbar fits: its last button is fully on screen.
    final more = tester.getRect(
      find.byKey(const ValueKey('subtitle-queue-more')),
    );
    expect(more.right, lessThanOrEqualTo(size.width));
    expect(
      find.byKey(const ValueKey('shared-sort-menu')),
      size.width >= 760 ? findsOneWidget : findsNothing,
    );
    expect(
      find.byKey(const ValueKey('subtitle-guide-new-rule')),
      expectGuide ? findsOneWidget : findsNothing,
    );

    if (interact != null) {
      await interact();
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
    }

    final dir = Platform.environment['CB_SCREENSHOT_DIR'];
    if (shot != null && dir != null) {
      await tester.runAsync(() async {
        final boundary =
            tester.renderObject(find.byKey(const ValueKey('shot')))
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          p.join(dir, '$shot.png'),
        ).writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      queue.dispose();
      await db.close();
    });
  }

  for (final size in [
    const Size(1280, 800),
    const Size(760, 900),
    const Size(400, 800),
    const Size(1280, 520),
    const Size(1000, 360),
    const Size(1280, 220),
  ]) {
    testWidgets('lays out with jobs and rules at ${size.width}', (
      tester,
    ) async {
      await render(
        tester,
        size: size,
        withData: true,
        shot: 'queue-${size.width.toInt()}x${size.height.toInt()}',
        vietnamese: true,
      );
    });
  }

  testWidgets('first run shows the guide with the address bar', (tester) async {
    await render(
      tester,
      size: const Size(1280, 800),
      withData: false,
      shot: 'queue-empty',
    );
  });

  for (final mode in ['details', 'tiles', 'grid']) {
    for (final size in [const Size(1280, 800), const Size(400, 800)]) {
      testWidgets('$mode view lays out at ${size.width}', (tester) async {
        final previous = VisibilityDetectorController.instance.updateInterval;
        VisibilityDetectorController.instance.updateInterval = Duration.zero;
        addTearDown(
          () => VisibilityDetectorController.instance.updateInterval = previous,
        );
        await render(
          tester,
          size: size,
          withData: true,
          vietnamese: true,
          shot: 'queue-$mode-${size.width.toInt()}',
          initialPrefs: {'subtitle_queue.viewMode': mode},
        );
      });
    }
  }

  testWidgets('Grid mode uses source video thumbnails and persists', (
    tester,
  ) async {
    final previous = VisibilityDetectorController.instance.updateInterval;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    addTearDown(
      () => VisibilityDetectorController.instance.updateInterval = previous,
    );
    await render(
      tester,
      size: const Size(1280, 800),
      withData: true,
      interact: () async {
        expect(find.byType(ThumbnailLoader), findsNothing);
        await tester.tap(find.byKey(const ValueKey('shared-view-mode-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Grid'));
        await tester.pumpAndSettle();

        final thumbnails = tester.widgetList<ThumbnailLoader>(
          find.byType(ThumbnailLoader),
        );
        expect(thumbnails, isNotEmpty);
        expect(thumbnails.every((t) => t.isVideo && !t.isImage), isTrue);
        expect(
          thumbnails.every(
            (t) => t.filePath.endsWith('.mkv') || t.filePath.endsWith('.mp4'),
          ),
          isTrue,
        );
        final card = find.ancestor(
          of: find.byType(ThumbnailLoader).first,
          matching: find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value.startsWith('subtitle-job:'),
          ),
        );
        expect(
          find.descendant(
            of: card,
            matching: find.byType(LinearProgressIndicator),
          ),
          findsOneWidget,
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        expect(
          find.descendant(of: card, matching: find.byType(RawImage)),
          findsWidgets,
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('subtitle_queue.viewMode'), 'grid');

        await tester.tap(find.byKey(const ValueKey('shared-view-mode-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('List'));
        await tester.pumpAndSettle();
        expect(find.byType(ThumbnailLoader), findsNothing);
        expect(prefs.getString('subtitle_queue.viewMode'), 'list');
      },
    );
  });

  testWidgets('sorting by a details column and searching', (tester) async {
    await render(
      tester,
      size: const Size(1280, 800),
      withData: true,
      shot: 'queue-sorted-search',
      initialPrefs: {'subtitle_queue.viewMode': 'details'},
      interact: () async {
        List<String> names() => [
          for (final e
              in find
                  .byWidgetPredicate(
                    (w) =>
                        w.key is ValueKey<String> &&
                        (w.key! as ValueKey<String>).value.startsWith(
                          'subtitle-job:',
                        ),
                  )
                  .evaluate())
            e.widget.key.toString(),
        ];
        final before = names();
        await tester.tap(find.byKey(const ValueKey('subtitle-column-name')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('subtitle-column-name')));
        await tester.pump();
        expect(names(), isNot(before), reason: 'descending by name');
        await tester.tap(find.byKey(const ValueKey('shared-search-action')));
        await tester.pump();
        await tester.pump();
        await tester.enterText(
          find.descendant(
            of: find.byKey(const ValueKey('subtitle-queue-search')),
            matching: find.byType(EditableText),
          ),
          'E05',
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(names(), hasLength(1));
      },
    );
  });

  testWidgets('source location opens original video, not generated SRT', (
    tester,
  ) async {
    late SubtitleBatchStore store;
    await render(
      tester,
      size: const Size(1280, 800),
      withData: true,
      onStore: (value) => store = value,
      interact: () async {
        final done = await tester.runAsync(
          () async =>
              (await store.jobs(statuses: {SubtitleBatchStatus.done})).single,
        );
        expect(done!.outputPath, isNotNull);
        await tester.tap(find.byKey(const ValueKey('shared-search-action')));
        await tester.pump();
        await tester.pump();
        await tester.enterText(
          find.descendant(
            of: find.byKey(const ValueKey('subtitle-queue-search')),
            matching: find.byType(EditableText),
          ),
          'E02',
        );
        await tester.pump(const Duration(milliseconds: 400));
        final button = find.byKey(
          ValueKey('subtitle-source-folder:${done.id}'),
        );
        expect(button, findsOneWidget);
        final tabs = BlocProvider.of<TabManagerBloc>(
          tester.element(find.byType(SubtitleQueueScreen)),
        );
        await tester.tap(button);
        await tester.pump();
        expect(tabs.state.activeTab?.path, p.dirname(done.path));
        expect(
          tabs.state.activeTab?.highlightedFileName,
          p.basename(done.path),
        );
      },
    );
  });

  testWidgets('clean generated subtitles asks for confirmation', (
    tester,
  ) async {
    late SubtitleBatchStore store;
    await render(
      tester,
      size: const Size(1280, 800),
      withData: true,
      onStore: (value) => store = value,
      interact: () async {
        // The default fixture includes a running job. Wait until it is back
        // in the pending queue before cleaning.
        await tester.runAsync(() async {
          for (final job in await store.jobs(
            statuses: {SubtitleBatchStatus.running},
          )) {
            await store.requeue(job);
          }
        });
        await tester.pump(const Duration(milliseconds: 1600));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('subtitle-queue-clean-generated')),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Original videos'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Original videos'), findsNothing);
      },
    );
  });

  testWidgets('clicking a rule shows only its videos', (tester) async {
    await render(
      tester,
      size: const Size(1280, 800),
      withData: true,
      shot: 'queue-rule-filter',
      vietnamese: true,
      interact: () async {
        int rows() => find
            .byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith(
                    'subtitle-job:',
                  ),
            )
            .evaluate()
            .length;
        expect(rows(), greaterThan(2));
        await tester.tap(find.text('Lectures'));
        await tester.pump();
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)),
          );
          await tester.pump();
        }
        expect(rows(), 2);
        expect(find.text('Lecture 01.mp4'), findsOneWidget);
        expect(find.text('Show S01E04.mkv'), findsNothing);
      },
    );
  });

  testWidgets(
    'deleting the selected rule removes its tile and jobs immediately',
    (tester) async {
      late SubtitleBatchStore store;
      await render(
        tester,
        size: const Size(1280, 800),
        withData: true,
        onStore: (value) => store = value,
        interact: () async {
          final rule = (await tester.runAsync(
            () async =>
                (await store.rules()).firstWhere((r) => r.name == 'Lectures'),
          ))!;
          final tile = find.byKey(ValueKey('subtitle-rule:${rule.id}'));
          await tester.tap(tile);
          await tester.pump();
          await tester.tap(
            find.descendant(of: tile, matching: find.byTooltip('More options')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Delete').last);
          await tester.pumpAndSettle();
          expect(find.textContaining('Lectures'), findsWidgets);
          await tester.tap(find.text('Delete').last);
          await tester.pumpAndSettle();
          for (var i = 0; i < 5; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 60)),
            );
            await tester.pump();
          }
          final remaining = await tester.runAsync(store.rules);
          expect(remaining!.map((r) => r.id), isNot(contains(rule.id)));
          expect(tile, findsNothing);
          expect(find.text('Lecture 01.mp4'), findsNothing);
          // Deletion in another window produces no local queue event.
          // The existing periodic refresh must still remove the last rule.
          final last = remaining.single;
          await tester.runAsync(() => store.deleteRule(last.id!));
          await tester.pump(const Duration(milliseconds: 1600));
          for (var i = 0; i < 5; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 60)),
            );
            await tester.pump();
          }
          expect(
            find.byKey(ValueKey('subtitle-rule:${last.id}')),
            findsNothing,
          );
        },
      );
    },
  );

  testWidgets('Start runs the focused rule', (tester) async {
    late SubtitleBatchStore store;
    await render(
      tester,
      size: const Size(1280, 800),
      withData: true,
      shot: 'queue-start-rule',
      vietnamese: true,
      onStore: (value) => store = value,
      interact: () async {
        Future<void> settle() async {
          for (var i = 0; i < 4; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 60)),
            );
            await tester.pump();
          }
        }

        await tester.tap(find.text('Lectures'));
        await settle();
        expect(find.text('Chạy “Lectures”'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('subtitle-queue-start')));
        await settle();
        final rule = await tester.runAsync(store.runRule);
        final lectures = (await tester.runAsync(
          store.rules,
        ))!.firstWhere((r) => r.name == 'Lectures');
        expect(rule, lectures.id);
        expect(
          find.byKey(ValueKey('subtitle-rule-running:${lectures.id}')),
          findsOneWidget,
        );
        // Focusing another rule offers to run that one instead.
        await tester.tap(find.text('Anime season 1'));
        await settle();
        expect(find.text('Chạy “Anime season 1”'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('subtitle-queue-pause-other')),
          findsOneWidget,
        );
      },
    );
  });

  testWidgets('the more menu sets how many videos run at once', (tester) async {
    late SubtitleBatchStore store;
    await render(
      tester,
      size: const Size(1280, 800),
      withData: true,
      shot: 'queue-parallel-menu',
      vietnamese: true,
      onStore: (value) => store = value,
      interact: () async {
        Future<void> settle() async {
          for (var i = 0; i < 4; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 60)),
            );
            await tester.pump();
          }
        }

        await tester.tap(find.byKey(const ValueKey('subtitle-queue-more')));
        await settle();
        await tester.tap(find.text('Số video chạy cùng lúc'));
        await settle();
        expect(find.text('Tự động (đề xuất)'), findsOneWidget);
        expect(find.text('1 video'), findsOneWidget);
        await tester.tap(find.text('2 video'));
        await settle();
        expect(await tester.runAsync(store.parallelJobs), 2);
      },
    );
  });

  testWidgets('a failed video says why and opens the details', (tester) async {
    await render(
      tester,
      size: const Size(1280, 800),
      withData: true,
      shot: 'queue-failure',
      vietnamese: true,
      interact: () async {
        Future<void> settle() async {
          for (var i = 0; i < 4; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 60)),
            );
            await tester.pump();
          }
        }

        // Only the queue workload is shown, not the scaler's global load.
        expect(
          find.byKey(const ValueKey('subtitle-queue-resources')),
          findsOneWidget,
        );
        expect(find.text('11.0/64.0 GB'), findsNothing);
        expect(find.text('53.0/64.0 GB'), findsNothing);
        expect(find.text('99%'), findsNothing);
        expect(find.text('3.0/64.0 GB'), findsOneWidget);
        expect(find.text('12%'), findsOneWidget);
        expect(find.text('42%'), findsOneWidget);
        expect(find.text('5.0/16.0 GB'), findsOneWidget);
        expect(find.text('8.0 MB/s'), findsOneWidget);

        // Only the failed video.
        await tester.tap(find.text('Lỗi  1'));
        await settle();
        final reason = find.text('Không đọc được âm thanh');
        expect(reason, findsOneWidget);
        expect(find.text('Cannot read the video duration'), findsNothing);
        await tester.tap(reason);
        await settle();
        expect(
          find.textContaining('File bị hỏng hoặc dùng định dạng âm thanh'),
          findsWidgets,
        );
        final detail = tester.widget<SelectableText>(
          find.byKey(const ValueKey('subtitle-error-detail')),
        );
        expect(detail.data, 'Cannot read the video duration');
      },
    );
  });

  testWidgets('the guide opens the rule editor', (tester) async {
    await render(
      tester,
      size: const Size(1280, 900),
      withData: false,
      shot: 'rule-dialog',
      vietnamese: true,
      interact: () async {
        await tester.tap(find.byKey(const ValueKey('subtitle-guide-new-rule')));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('subtitle-rule-save')),
          findsOneWidget,
        );
      },
    );
  });
}
