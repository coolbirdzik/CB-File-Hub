import 'dart:io';
import 'dart:ui' as ui;

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/bloc/ai_agent/ai_agent_bloc.dart';
import 'package:cb_file_manager/bloc/ai_agent/ai_agent_event.dart';
import 'package:cb_file_manager/bloc/ai_agent/ai_agent_state.dart';
import 'package:cb_file_manager/models/ai/ai_provider_model.dart';
import 'package:cb_file_manager/services/ai/ai_provider_service.dart';
import 'package:cb_file_manager/ui/screens/ai_chat/ai_panel_controller.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_agent_review.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_service.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:cb_file_manager/services/disk_cleaner/full_disk_scan_isolate.dart';
import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cb_agent_cleaner_screen.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Cleaner extends DiskCleanerService {
  final DiskTreeNode root;
  _Cleaner(this.root)
    : super.forTesting(fullDiskScanSpawner: spawnFullDiskScan);

  @override
  Future<List<DriveSpace>> getDriveSpace() async => const [
    DriveSpace(path: r'C:\', label: 'Test', totalBytes: 10000, freeBytes: 5000),
  ];

  @override
  Future<FullDiskScanHandle> scanFullDisk({
    required String drivePath,
    int maxDepth = 20,
    int minDisplayEntryBytes = defaultMinDisplayEntryBytes,
    int maxChildrenPerDirectory = defaultMaxChildrenPerDirectory,
  }) async => FullDiskScanHandle.completed(
    drivePath: drivePath,
    result: FullDiskScanResult(root: root, duration: Duration.zero),
  );
}

class _ReviewBloc extends AiAgentBloc {
  final reviewRequests = <SendMessage>[];
  _ReviewBloc() : super(providerService: AiProviderService());
  void beginReview() => emit(const AiAgentState(isLoading: true));

  @override
  void add(AiAgentEvent event) {
    if (event is SendMessage) {
      reviewRequests.add(event);
      return;
    }
    super.add(event);
  }
}

class _AvailableProvider extends AiProviderService {
  @override
  Future<List<AiProviderConfig>> getEnabledProviders() async => const [
    AiProviderConfig(
      id: 'test',
      name: 'Test',
      apiType: AiApiType.openaiCompatible,
      apiKey: '',
      endpoint: '',
      modelName: 'test',
      createdAt: 0,
      updatedAt: 0,
    ),
  ];
}

class _Panel extends AiPanelController {
  final AiAgentBloc reviewBloc;
  var openCalls = 0;
  _Panel(this.reviewBloc);

  @override
  void open({String? path, String? tabId}) {
    openCalls++;
    super.open(path: path, tabId: tabId);
  }

  @override
  AiAgentBloc blocForTab(
    String tabId, {
    String? initialPath,
    required List<String> thinkingPhrases,
    required String waitingApproval,
    required String runningToolTemplate,
  }) => reviewBloc;
}

void main() {
  testWidgets(
    'agent selection checks and reveals exact scan rows and keeps deletion behind review',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      GetIt.instance.pushNewScope();
      GetIt.instance.registerSingleton<AiProviderService>(_AvailableProvider());
      addTearDown(GetIt.instance.popScope);
      if (Platform.environment['CB_CLEANER_REVIEW_PREVIEW'] == 'true') {
        await tester.runAsync(() async {
          final textFont = FontLoader('CleanerPreview');
          textFont.addFont(
            File(
              r'C:\Windows\Fonts\segoeui.ttf',
            ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
          );
          await textFont.load();
          final iconFont = FontLoader(
            'packages/phosphor_flutter/PhosphorLight',
          );
          iconFont.addFont(
            rootBundle.load(
              'packages/phosphor_flutter/lib/fonts/Phosphor-Light.ttf',
            ),
          );
          await iconFont.load();
        });
      }
      tester.view.physicalSize = const Size(1800, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final first = DiskTreeNode(
        name: 'first.tmp',
        fullPath: r'C:\Cache\first.tmp',
        isFile: true,
        sizeBytes: 100,
        fileCount: 1,
        junkCategoryId: 'windows_temp',
      );
      final second = DiskTreeNode(
        name: 'second.tmp',
        fullPath: r'C:\Cache\second.tmp',
        isFile: true,
        sizeBytes: 200,
        fileCount: 1,
        junkCategoryId: 'windows_temp',
      );
      final cache = DiskTreeNode(
        name: 'Cache',
        fullPath: r'C:\Cache',
        sizeBytes: 300,
        fileCount: 2,
        children: [first, second],
      );
      final personal = DiskTreeNode(
        name: 'keep.iso',
        fullPath: r'C:\keep.iso',
        isFile: true,
        sizeBytes: 400,
        fileCount: 1,
      );
      final root = DiskTreeNode(
        name: r'C:\',
        fullPath: r'C:\',
        sizeBytes: 700,
        fileCount: 3,
        children: [personal, cache],
        isExpanded: true,
      );
      final cleaner = _Cleaner(root);
      final reviewBloc = _ReviewBloc();
      final panel = _Panel(reviewBloc);
      addTearDown(reviewBloc.close);
      addTearDown(panel.dispose);
      final tabs = TabManagerBloc()..add(AddTab(path: '#cb-agent-cleaner'));
      await tester.pump();
      addTearDown(tabs.close);
      final tabId = tabs.state.activeTabId!;

      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('cleaner-preview-boundary'),
          child: AiPanelScope(
            controller: panel,
            child: BlocProvider.value(
              value: tabs,
              child: MaterialApp(
                theme: ThemeData(
                  fontFamily:
                      Platform.environment['CB_CLEANER_REVIEW_PREVIEW'] ==
                          'true'
                      ? 'CleanerPreview'
                      : null,
                ),
                locale: const Locale('en'),
                supportedLocales: const [Locale('en'), Locale('vi')],
                localizationsDelegates: const [
                  AppLocalizationsDelegate(),
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: Scaffold(
                  body: CbAgentCleanerScreen(
                    tabId: tabId,
                    cleanerService: cleaner,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cleaner-scan-cta')));
      await tester.pumpAndSettle();

      expect(find.text('Quick review'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('cleaner-agent-select-recommendations')),
      );
      // Open the chat synchronously, before review processing or a new frame.
      expect(panel.openCalls, 1);
      expect(panel.isOpen, isTrue);
      expect(panel.ownerTabId, tabId);
      expect(panel.currentPath, '#cb-agent-cleaner');
      await tester.pumpAndSettle();
      expect(panel.openCalls, 1);
      expect(panel.isOpen, isTrue);
      expect(reviewBloc.reviewRequests, hasLength(1));
      expect(reviewBloc.reviewRequests.single.reviewEntireCleanerScan, isTrue);

      expect(find.text('first.tmp'), findsNothing);
      await tester.tap(find.text('keep.iso').first);
      await tester.pumpAndSettle();
      expect(personal.isSelectedForDeletion, isTrue);

      CleanerItemInteractionResult interact(
        DiskTreeNode node, [
        CleanerItemAnalysis? analysis,
      ]) => cleaner.interactWithCleanerScanItem(
        ownerTabId: tabId,
        scanId: cleaner.getCleanerScanContext(ownerTabId: tabId)!.scanId,
        path: node.fullPath,
        analysis: analysis,
      );
      reviewBloc.beginReview();
      expect(interact(first).error, isNull);
      await tester.pump(const Duration(milliseconds: 200));
      final reviewingButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('cleaner-agent-select-recommendations')),
      );
      expect(reviewingButton.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(
        find.byKey(ValueKey('cleaner-agent-inspecting-${first.fullPath}')),
        findsOneWidget,
      );
      expect(first.isSelectedForDeletion, isFalse);
      expect(personal.isSelectedForDeletion, isTrue);
      reviewBloc.add(const StopGeneration());
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('cleaner-agent-inspecting-${first.fullPath}')),
        findsNothing,
      );
      expect(first.isSelectedForDeletion, isFalse);
      expect(interact(first).error, isNull);
      const firstAnalysis = CleanerItemAnalysis(
        decision: CleanerItemDecision.clean,
        reason:
            'Temporary application data can be recreated. Close the app before cleaning.',
        selectForCleanup: true,
      );
      expect(interact(first, firstAnalysis).error, isNull);
      await tester.pumpAndSettle();
      expect(first.isSelectedForDeletion, isTrue);
      expect(find.text(firstAnalysis.reason), findsOneWidget);
      expect(
        find.byKey(ValueKey('cleaner-agent-inspecting-${first.fullPath}')),
        findsNothing,
      );

      expect(interact(second).error, isNull);
      const secondAnalysis = CleanerItemAnalysis(
        decision: CleanerItemDecision.review,
        reason:
            'This file may belong to an active session. Review it before choosing to delete.',
      );
      expect(interact(second, secondAnalysis).error, isNull);
      expect(interact(personal).error, isNull);
      const personalAnalysis = CleanerItemAnalysis(
        decision: CleanerItemDecision.keep,
        reason:
            'This is a personal disk image. Its size does not establish that it is disposable.',
      );
      expect(interact(personal, personalAnalysis).error, isNull);
      await tester.pumpAndSettle();
      expect(second.isSelectedForDeletion, isFalse);
      expect(
        personal.isSelectedForDeletion,
        isTrue,
      ); // Preserve the user's explicit check.
      expect(
        find.byKey(ValueKey('cleaner-agent-analysis-${personal.fullPath}')),
        findsOneWidget,
      );
      expect(cleaner.pendingCleanupBytes, 0);

      if (Platform.environment['CB_CLEANER_REVIEW_PREVIEW'] == 'true') {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('cleaner-preview-boundary')),
        );
        await tester.runAsync(() async {
          final preview = await boundary.toImage();
          final bytes = await preview.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File(
            'build/cleaner_agent_review_preview.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          preview.dispose();
        });
      }

      // Opening an assessment reveals its row without changing cleanup checks.
      await tester.tap(
        find.byKey(ValueKey('cleaner-agent-analysis-${personal.fullPath}')),
      );
      await tester.pumpAndSettle();
      expect(first.isSelectedForDeletion, isTrue);
      expect(second.isSelectedForDeletion, isFalse);
      expect(interact(first).error, isNull);
      expect(interact(first, secondAnalysis).error, isNull);
      await tester.pumpAndSettle();
      expect(
        first.isSelectedForDeletion,
        isFalse,
      ); // Withdraw the agent's own old recommendation.

      CleanerSelectionResult select(
        List<String> paths, {
        bool replace = true,
      }) => cleaner.selectCleanerScanItems(
        ownerTabId: tabId,
        scanId: cleaner.getCleanerScanContext(ownerTabId: tabId)!.scanId,
        paths: paths,
        replace: replace,
      );
      final selection = select([first.fullPath, second.fullPath]);
      expect(selection.error, isNull);
      expect(selection.selected, [first, second]);
      await tester.pumpAndSettle();
      expect(personal.isSelectedForDeletion, isFalse);
      expect(cache.isExpanded, isTrue);
      for (final node in [first, second]) {
        expect(
          find.byKey(ValueKey('cleaner-tree-row-selected-${node.fullPath}')),
          findsOneWidget,
        );
      }
      expect(cleaner.pendingCleanupItems, isEmpty);
      expect(cleaner.pendingCleanupBytes, 0);

      // Group verdicts select safe members and preserve explicit user checks.
      expect(select([personal.fullPath]).error, isNull);
      final fullReview = cleaner.beginFullCleanerReview(tabId);
      await fullReview.prepareGroups(checkActive: () {});
      final safeGroup = fullReview.groups.firstWhere(
        (group) => group.nodes.contains(first),
      );
      expect(safeGroup.nodes, containsAll([first, second]));
      expect(interact(safeGroup.representative).error, isNull);
      cleaner.applyFullReviewGroup(
        ownerTabId: tabId,
        review: fullReview,
        group: safeGroup,
        analysis: firstAnalysis,
      );
      await tester.pumpAndSettle();
      expect(first.isSelectedForDeletion, isTrue);
      expect(second.isSelectedForDeletion, isTrue);
      expect(personal.isSelectedForDeletion, isTrue);
      expect(fullReview.analysisForPath(first.fullPath), same(firstAnalysis));
      expect(find.text('2 entries assessed together'), findsOneWidget);
      expect(interact(safeGroup.representative).error, isNull);
      cleaner.applyFullReviewGroup(
        ownerTabId: tabId,
        review: fullReview,
        group: safeGroup,
        analysis: secondAnalysis,
      );
      await tester.pumpAndSettle();
      expect(first.isSelectedForDeletion, isFalse);
      expect(second.isSelectedForDeletion, isFalse);
      expect(personal.isSelectedForDeletion, isTrue);
      expect(fullReview.analysisForPath(first.fullPath), same(secondAnalysis));
      expect(select([first.fullPath, second.fullPath]).error, isNull);
      await tester.pumpAndSettle();

      // A completed group review exposes the visual overview in the main
      // results area. Its navigation preserves the user's exact checks.
      expect(
        find.byKey(const ValueKey('cleaner-review-overview')),
        findsNothing,
      );
      for (final group in fullReview.groups.where((g) => g.analysis == null)) {
        expect(interact(group.representative).error, isNull);
        cleaner.applyFullReviewGroup(
          ownerTabId: tabId,
          review: fullReview,
          group: group,
          analysis: personalAnalysis,
        );
      }
      await tester.pumpAndSettle();
      expect(fullReview.isComplete, isTrue);
      expect(
        find.byKey(const ValueKey('cleaner-review-overview')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(ValueKey('cleaner-summary-${safeGroup.id}')));
      await tester.pumpAndSettle();
      expect(first.isSelectedForDeletion, isTrue);
      expect(second.isSelectedForDeletion, isTrue);
      expect(personal.isSelectedForDeletion, isFalse);
      expect(tester.takeException(), isNull);

      // A response arriving after the user switches tabs cannot modify this tree.
      tabs.add(AddTab(path: '#home'));
      await tester.pumpAndSettle();
      expect(select([personal.fullPath]).error, isNotNull);
      expect(first.isSelectedForDeletion, isTrue);
      tabs.add(SwitchToTab(tabId));
      await tester.pumpAndSettle();

      // Selecting a parent and its child represents exactly one cleanup target.
      final canonical = select([first.fullPath, cache.fullPath]);
      expect(canonical.selected, [cache]);
      await tester.pumpAndSettle();
      expect(first.isSelectedForDeletion, isFalse);
      expect(second.isSelectedForDeletion, isFalse);
      expect(select([personal.fullPath], replace: false).selected, [
        cache,
        personal,
      ]);
      await tester.pumpAndSettle();

      final review = find.byKey(const ValueKey('cleaner-review-and-clean'));
      expect(tester.widget<FilledButton>(review).onPressed, isNotNull);
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(cleaner.pendingCleanupItems!.map((item) => item.path), [
        cache.fullPath,
        personal.fullPath,
      ]);
      expect(cleaner.pendingCleanupBytes, 700);
      expect(select([first.fullPath]).error, isNotNull);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(cleaner.getCleanerScanContext(ownerTabId: tabId), isNull);
    },
  );
}
