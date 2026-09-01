import 'package:cb_file_manager/ui/components/video/video_player/video_player_advanced_menu.dart';
import 'package:cb_file_manager/ui/components/video/video_player/video_player_control_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

void main() {
  testWidgets('player control tooltips keep distinct traversal parents',
      (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: <Widget>[
              VideoPlayerControlButton(
                icon: PhosphorIconsLight.skipBack,
                onPressed: () {},
                tooltip: 'Rewind 10s',
              ),
              VideoPlayerControlButton(
                icon: PhosphorIconsLight.speakerHigh,
                onPressed: () {},
                tooltip: 'Mute',
              ),
              VideoPlayerControlButton(
                icon: PhosphorIconsLight.cornersOut,
                onPressed: () {},
                tooltip: 'Enter fullscreen',
              ),
              const VideoPlayerAdvancedMenu(),
            ],
          ),
        ),
      ),
    );

    final traversalParents = _tooltipTraversalParents(tester);
    expect(traversalParents, hasLength(4));
    expect(find.byTooltip('Rewind 10s'), findsOneWidget);
    expect(find.byTooltip('Mute'), findsOneWidget);
    expect(find.byTooltip('Enter fullscreen'), findsOneWidget);
    expect(find.byTooltip('Advanced Controls'), findsOneWidget);

    handle.dispose();
  });

  testWidgets('desktop player row keeps all five overlay traversal parents',
      (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: <Widget>[
              Expanded(
                child: Slider(
                  value: 25,
                  min: 0,
                  max: 100,
                  onChanged: (_) {},
                ),
              ),
              VideoPlayerControlButton(
                icon: PhosphorIconsLight.speakerHigh,
                onPressed: () {},
                tooltip: 'Mute',
              ),
              SizedBox(
                width: 80,
                child: VideoPlayerVolumeSlider(
                  value: 70,
                  onChanged: (_) {},
                ),
              ),
              const VideoPlayerAdvancedMenu(),
              VideoPlayerControlButton(
                icon: PhosphorIconsLight.cornersOut,
                onPressed: () {},
                tooltip: 'Enter fullscreen',
              ),
            ],
          ),
        ),
      ),
    );

    expect(_tooltipTraversalParents(tester), hasLength(5));
    handle.dispose();
  });
}

Set<Object> _tooltipTraversalParents(WidgetTester tester) {
  final root =
      tester.binding.renderViews.first.owner?.semanticsOwner?.rootSemanticsNode;
  expect(root, isNotNull);

  final traversalParents = <Object>{};
  void collect(SemanticsNode node) {
    final identifier = node.getSemanticsData().traversalParentIdentifier;
    if (identifier != null) traversalParents.add(identifier);
    node.visitChildren((child) {
      collect(child);
      return true;
    });
  }

  collect(root!);
  return traversalParents;
}
