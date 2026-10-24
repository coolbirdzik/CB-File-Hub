import 'dart:ui' as ui;

import 'package:cb_file_manager/design_system/primitives/cb_slider.dart';
import 'package:cb_file_manager/ui/components/video/video_player/video_player_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _SemanticsBinding extends AutomatedTestWidgetsFlutterBinding {
  final nodes = <int, List<int>>{};
  final errors = <String>[];

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() =>
      _UpdateProbe(this);
}

// Validate incremental serialized updates, including nodes that the render-tree
// snapshot silently drops. These unreachable nodes are rejected by AXTree.
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

  testWidgets('filter slider dialog serializes no orphan accessibility nodes', (
    tester,
  ) async {
    binding.nodes.clear();
    binding.errors.clear();
    final semantics = tester.ensureSemantics();
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold(body: Text('Video'));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    showDialog<void>(
      context: pageContext,
      builder: (_) => AlertDialog(
        content: VideoPlayerFilterSlider(
          label: 'Brightness',
          value: 1,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(binding.errors, isEmpty);
    Navigator.of(pageContext).pop();
    await tester.pumpAndSettle();
    expect(binding.errors, isEmpty);
    semantics.dispose();
  });

  for (final dialog in [true, false]) {
    for (final labeled in [true, false]) {
      testWidgets('slider stays accessible through drag, keys and removal '
          '(dialog=$dialog, labeled=$labeled)', (tester) async {
        binding.nodes.clear();
        binding.errors.clear();
        final semantics = tester.ensureSemantics();
        final focus = FocusNode();
        try {
          late BuildContext pageContext;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(
                platform: TargetPlatform.windows,
                sliderTheme: const SliderThemeData(
                  showValueIndicator: ShowValueIndicator.onDrag,
                ),
              ),
              home: Builder(
                builder: (context) {
                  pageContext = context;
                  return const Scaffold(body: Text('Home'));
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (var cycle = 0; cycle < 2; cycle++) {
            var value = 0.5;
            var starts = 0;
            var ends = 0;
            final content = StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 300,
                      child: CbSlider(
                        value: value,
                        divisions: labeled ? 20 : null,
                        label: labeled ? '${(value * 100).round()}%' : null,
                        focusNode: focus,
                        semanticFormatterCallback: (v) =>
                            '${(v * 100).round()} percent',
                        onChangeStart: (_) => starts++,
                        onChanged: (v) => setState(() => value = v),
                        onChangeEnd: (_) => ends++,
                      ),
                    ),
                  ],
                );
              },
            );
            if (dialog) {
              showDialog<void>(
                context: pageContext,
                builder: (_) => AlertDialog(content: content),
              );
            } else {
              Navigator.of(pageContext).push<void>(
                MaterialPageRoute(
                  builder: (_) => Scaffold(body: Center(child: content)),
                ),
              );
            }
            await tester.pumpAndSettle();
            expect(binding.errors, isEmpty);
            final slider = find.byType(Slider);
            expect(tester.getSize(slider).height, lessThan(100));
            final data = _sliderSemantics(tester);
            expect(data.value, '50 percent');
            expect(data.hasAction(ui.SemanticsAction.increase), isTrue);
            expect(data.hasAction(ui.SemanticsAction.decrease), isTrue);

            final gesture = await tester.startGesture(tester.getCenter(slider));
            await gesture.moveBy(const Offset(35, 0));
            await tester.pump(const Duration(milliseconds: 300));
            expect(value, greaterThan(0.5));
            expect(starts, 1);
            expect(binding.errors, isEmpty);
            await gesture.up();
            await tester.pumpAndSettle();
            expect(ends, 1);

            focus.requestFocus();
            await tester.pumpAndSettle();
            expect(focus.hasFocus, isTrue);
            final beforeKey = value;
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            await tester.pumpAndSettle();
            expect(value, greaterThan(beforeKey));
            expect(binding.errors, isEmpty);
            Navigator.of(pageContext).pop();
            await tester.pumpAndSettle();
            expect(binding.errors, isEmpty);
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          semantics.dispose();
          focus.dispose();
        }
      });
    }
  }
}

SemanticsData _sliderSemantics(WidgetTester tester) {
  final sliders = <SemanticsData>[];
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.flagsCollection.isSlider) sliders.add(data);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return sliders.single;
}
