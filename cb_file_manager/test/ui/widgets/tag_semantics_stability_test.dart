import 'dart:ui' as ui;

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/ui/widgets/chips_input.dart';
import 'package:cb_file_manager/ui/widgets/resizable_dialog.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_content_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

class _SemanticsBinding extends AutomatedTestWidgetsFlutterBinding {
  final nodes = <int, List<int>>{};
  final errors = <String>[];

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() =>
      _UpdateProbe(this);
}

// Check the serialized traversal graph, not just the RenderObject tree. The
// latter can look valid while a hidden portal sends an unreachable node to the
// Windows accessibility bridge. Match its incremental-update contract.
class _UpdateProbe extends Fake implements ui.SemanticsUpdateBuilder {
  _UpdateProbe(this.binding);
  final _SemanticsBinding binding;
  final updated = <int>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #updateNode) {
      final args = invocation.namedArguments;
      final id = args[#id] as int;
      binding.nodes[id] = List<int>.from(
        args[#childrenInTraversalOrder] as Iterable,
      );
      updated.add(id);
      return null;
    }
    if (invocation.memberName == #updateCustomAction) return null;
    return super.noSuchMethod(invocation);
  }

  @override
  ui.SemanticsUpdate build() {
    final reachable = <int>{};
    void visit(int id) {
      if (!reachable.add(id)) return;
      for (final child in binding.nodes[id] ?? <int>[]) {
        visit(child);
      }
    }

    visit(0);
    for (final id in updated) {
      if (!reachable.contains(id)) binding.errors.add('orphan node $id');
    }
    for (final id in reachable) {
      if (!binding.nodes.containsKey(id)) {
        binding.errors.add('missing node $id');
      }
    }
    binding.nodes.removeWhere((id, _) => !reachable.contains(id));
    return ui.SemanticsUpdateBuilder().build();
  }
}

void main() {
  final binding = _SemanticsBinding();
  for (final scoped in [false, true]) {
    for (final removedIndex in [0, 2]) {
      testWidgets(
        'deleting chip $removedIndex preserves visible chips (scoped=$scoped)',
        (tester) async {
          final semantics = tester.ensureSemantics();
          binding.nodes.clear();
          binding.errors.clear();
          final key = GlobalKey<ChipsInputState<String>>();
          var tags = <String>[
            'Fukada Eimi',
            'xanh dương',
            'xanh dương nhạt',
            'Trắng',
            'thấy dây',
          ];
          late StateSetter update;
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: const [AppLocalizationsDelegate()],
              supportedLocales: const [Locale('en')],
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return ChipsInput<String>(
                      key: key,
                      values: tags,
                      scopeParent: scoped ? 'People' : null,
                      onChanged: (values) => setState(() => tags = values),
                      chipBuilder: (context, tag) => TagInputChip(
                        tag: tag,
                        onDeleted: (removed) => setState(
                          () => tags = tags.where((t) => t != removed).toList(),
                        ),
                        onSelected: (_) {},
                      ),
                    );
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byType(TextField));
          final controller = key.currentState!.controller;
          final prefix = controller.prefixFor(valueCount: tags.length);
          tester.testTextInput.updateEditingValue(
            TextEditingValue(
              text: '${prefix}nhạt',
              selection: TextSelection.collapsed(offset: prefix.length + 4),
            ),
          );
          await tester.pumpAndSettle();

          Finder chip(String tag) => find.widgetWithText(TagInputChip, tag);
          Future<void> remove(String tag) async {
            await tester.tap(
              find.descendant(
                of: chip(tag),
                matching: find.byWidgetPredicate(
                  (widget) => widget is GestureDetector && widget.child is Icon,
                ),
              ),
            );
            await tester.pumpAndSettle();
          }

          final removed = tags[removedIndex];
          await remove(removed);
          expect(chip(removed), findsNothing);
          for (final tag in tags) {
            final opacity = tester.widget<Opacity>(
              find.descendant(of: chip(tag), matching: find.byType(Opacity)),
            );
            expect(opacity.opacity, 1, reason: '$tag must remain painted');
          }
          expect(controller.textWithoutReplacements, 'nhạt');
          expect(
            controller.selection.extentOffset,
            controller.prefixFor(valueCount: tags.length).length + 4,
          );

          // A removed tag can be added again and deleted again; the remaining
          // chips must keep working after each animated removal.
          update(() => tags = [...tags, removed]);
          await tester.pumpAndSettle();
          for (final tag in [...tags]) {
            await remove(tag);
            expect(chip(tag), findsNothing);
          }
          expect(controller.textWithoutReplacements, 'nhạt');
          expect(find.byType(TagInputChip), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          semantics.dispose();
          expect(binding.errors, isEmpty);
        },
      );
    }
  }
  testWidgets('inactive tab sliders never emit orphan overlay nodes', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    binding.nodes.clear();
    binding.errors.clear();
    var activeTab = 0;
    var showSettings = true;
    var fileLabel = 'Files';
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return IndexedStack(
              index: activeTab,
              children: [
                TabContentOverlay(
                  key: const ValueKey('files'),
                  child: Text(fileLabel),
                ),
                if (showSettings)
                  TabContentOverlay(
                    key: const ValueKey('settings'),
                    child: Material(
                      child: ListView(
                        children: [
                          Slider(
                            value: 20,
                            min: 0,
                            max: 100,
                            onChanged: (_) {},
                          ),
                          Slider(
                            value: 40,
                            min: 0,
                            max: 100,
                            onChanged: (_) {},
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final sliders = tester
        .stateList(find.byType(Slider, skipOffstage: false))
        .toList();
    for (var i = 0; i < 5; i++) {
      update(() => activeTab = 1);
      await tester.pumpAndSettle();
      update(() => activeTab = 0);
      await tester.pumpAndSettle();
      final reassembly = tester.binding.reassembleApplication();
      await tester.pumpAndSettle();
      await reassembly;
      expect(tester.takeException(), isNull);
    }
    expect(
      tester.stateList(find.byType(Slider, skipOffstage: false)).toList(),
      sliders,
      reason: 'switching tabs must preserve slider state',
    );
    update(() => fileLabel = 'Files updated');
    await tester.pumpAndSettle();
    expect(find.text('Files updated'), findsOneWidget);
    update(() => showSettings = false);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    semantics.dispose();
    expect(binding.errors, isEmpty);
  });
  testWidgets('tag input semantics survive edits and dialog reassembly', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    binding.nodes.clear();
    binding.errors.clear();
    var tags = <String>['first', 'second', 'third'];
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return ResizableDialog(
              title: const Text('Manage tags'),
              contentBuilder: (context, size) => ChipsInput<String>(
                values: tags,
                onChanged: (values) => setState(() => tags = values),
                chipBuilder: (context, tag) => TagInputChip(
                  tag: tag,
                  onDeleted: (tag) => setState(() => tags.remove(tag)),
                  onSelected: (_) {},
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    for (final tooltip in find.byType(Tooltip).evaluate().toList()) {
      await mouse.moveTo(tester.getCenter(find.byWidget(tooltip.widget)));
      await tester.pump(const Duration(seconds: 1));
    }
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      update(() => tags = ['added $i', ...tags]);
      await tester.pumpAndSettle();
      update(() => tags = tags.reversed.skip(1).toList());
      await tester.pumpAndSettle();
      final reassembly = tester.binding.reassembleApplication();
      await tester.pumpAndSettle();
      await reassembly;
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
    semantics.dispose();
    expect(binding.errors, isEmpty);
  });
}
