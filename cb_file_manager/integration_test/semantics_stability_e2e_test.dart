// Guards the semantics tree against identity churn.
//
// The Windows AccessibilityBridge cannot serialize an ui::AXTreeUpdate that
// destroys node ids and reclaims their slots in the same frame; when that
// happens it drops the whole batch and floods stderr with
// "Failed to update ui::AXTree, error: Nodes left pending by the update: ...".
//
// Nodes legitimately come and go as content changes. What must never happen is
// a node being destroyed and an identical one (same label, same rect) created
// in the same frame — that is a remount, i.e. pure churn with nothing to show
// for it. A ValueKey built from mutable state used to do exactly that to the
// drawer sections on every tab switch.
//
// Not part of the CI E2E run (tool/e2e_parallel.dart names its files
// explicitly). Run it with: just e2e-file semantics_stability_e2e_test
import 'dart:io';

import 'package:cb_file_manager/e2e/cb_e2e_config.dart';
import 'package:cb_file_manager/main.dart';
import 'package:cb_file_manager/services/windowing/window_startup_payload.dart';
import 'package:cb_file_manager/ui/widgets/lazy_video_thumbnail.dart';
import 'package:cb_file_manager/ui/widgets/thumbnail_loader.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'e2e_helpers.dart';

class _NodeSnap {
  _NodeSnap(this.label, this.rect, this.childIds, this.parentId,
      this.traversalParent, this.traversalChild);
  final String label;
  final Rect rect;
  final List<int> childIds;
  final int? parentId;

  /// Set on an [OverlayPortal] anchor; the overlay child it owns points back at
  /// it through [traversalChild]. An anchor that gets merged into another node
  /// loses this, orphaning the overlay child.
  final Object? traversalParent;

  /// Set on the subtree an [OverlayPortal] parked in the [Overlay]. It names the
  /// anchor this subtree must be re-parented under for traversal.
  final Object? traversalChild;

  @override
  String toString() =>
      'label="$label" rect=$rect children=$childIds parent=$parentId';
}

/// The root [PipelineOwner] holds no render tree of its own — the view's owner
/// is a child of it, so pick the first one that actually has a semantics root.
SemanticsOwner? _semanticsOwner() {
  SemanticsOwner? found;
  void visit(PipelineOwner owner) {
    final candidate = owner.semanticsOwner;
    if (found == null && candidate?.rootSemanticsNode != null) {
      found = candidate;
    }
    owner.visitChildren(visit);
  }

  visit(RendererBinding.instance.rootPipelineOwner);
  return found;
}

Map<int, _NodeSnap> _snapshot() {
  final root = _semanticsOwner()?.rootSemanticsNode;
  final out = <int, _NodeSnap>{};
  if (root == null) return out;

  void walk(SemanticsNode node, int? parentId) {
    final children = <int>[];
    node.visitChildren((child) {
      children.add(child.id);
      return true;
    });
    final data = node.getSemanticsData();
    out[node.id] = _NodeSnap(data.label, node.rect, children, parentId,
        data.traversalParentIdentifier, data.traversalChildIdentifier);
    node.visitChildren((child) {
      walk(child, node.id);
      return true;
    });
  }

  walk(root, null);
  return out;
}

/// Smallest valid PNG (1x1, transparent).
final Uint8List _onePixelPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

/// The real sample MP4 shipped for the video E2E suite.
String _sampleVideoPath() {
  const name = 'file_example_MP4_1920_18MG.mp4';
  final candidates = <String>[];
  try {
    final script = Platform.script.toString();
    final scriptPath =
        script.startsWith('file:///') ? Uri.parse(script).toFilePath() : script;
    candidates.add(p.join(p.dirname(scriptPath), 'samples', name));
  } catch (_) {
    // Fall through to the working-directory candidates.
  }
  candidates
    ..add(p.join(Directory.current.path, 'integration_test', 'samples', name))
    ..add(p.join(Directory.current.path, 'samples', name));

  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
  }
  debugPrint('[AX] sample video not found, tried: $candidates');
  return '';
}

/// Best-effort: which widget owns [id] right now.
String _describeOwner(int id) {
  String? found;
  void visit(Element el) {
    if (found != null) return;
    final renderObject = el.renderObject;
    if (renderObject != null && renderObject.debugSemantics?.id == id) {
      final chain = <String>[];
      el.visitAncestorElements((a) {
        chain.add(a.widget.runtimeType.toString());
        return chain.length < 8;
      });
      found = '${el.widget.runtimeType} <- ${chain.join(' <- ')}';
      return;
    }
    el.visitChildren(visit);
  }

  final root = WidgetsBinding.instance.rootElement;
  if (root != null) visit(root);
  return found ?? '(element gone)';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AX semantics churn report', (WidgetTester tester) async {
    final handle = SemanticsBinding.instance.ensureSemantics();

    final dir = await Directory.systemTemp.createTemp('cb_ax_');
    for (var i = 0; i < 30; i++) {
      File('${dir.path}${Platform.pathSeparator}file_$i.txt')
          .writeAsStringSync('ax');
    }
    Directory('${dir.path}${Platform.pathSeparator}sub').createSync();

    // Video tiles are the interesting case: their thumbnail arrives later and
    // swaps a placeholder icon for an Image. The image must remain decorative
    // so that this visual-only transition does not change the semantics tree.
    final sample = File(_sampleVideoPath());
    var videoCount = 0;
    if (sample.existsSync()) {
      for (var i = 0; i < 3; i++) {
        sample.copySync('${dir.path}${Platform.pathSeparator}clip_$i.mp4');
        videoCount++;
      }
    }
    // Image tiles render their thumbnail immediately (no generation step), so
    // they exercise the same decorative-Image path deterministically.
    for (var i = 0; i < 8; i++) {
      File('${dir.path}${Platform.pathSeparator}pic_$i.png')
          .writeAsBytesSync(_onePixelPng);
    }
    debugPrint('[AX] sandbox videos=$videoCount images=8');

    CbE2EConfig.startupPayload = WindowStartupPayload(
      tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
    );

    var previous = <int, _NodeSnap>{};
    var phase = 'boot';
    var frames = 0;
    final churn = <String>[];
    final mixed = <String>[];
    final orphans = <String>[];

    void checkFrame() {
      frames++;
      final current = _snapshot();
      final added =
          current.keys.where((k) => !previous.containsKey(k)).toList();
      final removed =
          previous.keys.where((k) => !current.containsKey(k)).toList();

      if (added.isNotEmpty && removed.isNotEmpty) {
        final buffer = StringBuffer()
          ..writeln('[AX-MIXED] phase=$phase frame=$frames '
              '+${added.length} -${removed.length}');
        for (final id in added.take(4)) {
          buffer
              .writeln('    + $id ${current[id]}  owner=${_describeOwner(id)}');
        }
        for (final id in removed.take(4)) {
          buffer.writeln('    - $id ${previous[id]}');
        }
        mixed.add(buffer.toString());
      }

      for (final addedId in added) {
        final fresh = current[addedId]!;
        if (fresh.label.isEmpty) continue;
        for (final removedId in removed) {
          final gone = previous[removedId]!;
          if (gone.label != fresh.label || gone.rect != fresh.rect) continue;
          churn.add('[AX-CHURN] phase=$phase frame=$frames: node $removedId '
              'was destroyed and recreated as $addedId in one frame '
              '(${fresh.label} @ ${fresh.rect}) '
              'owner=${_describeOwner(addedId)}');
          break;
        }
      }

      // The "Nodes left pending by the update" flood. An OverlayPortal parks
      // its overlay child in the Overlay and tags it with
      // `traversalChildIdentifier`; the anchor carries the matching
      // `traversalParentIdentifier` so the child is re-parented under it for
      // traversal. If the anchor node is merged into a sibling or an ancestor,
      // that identifier disappears and the overlay subtree names a traversal
      // parent that is not in the tree. Flutter still sends it, the Windows
      // AccessibilityBridge cannot attach it, and it rejects the whole batch.
      final anchors = <Object>{};
      for (final snap in current.values) {
        final anchor = snap.traversalParent;
        if (anchor != null) anchors.add(anchor);
      }
      for (final entry in current.entries) {
        final wanted = entry.value.traversalChild;
        if (wanted == null || anchors.contains(wanted)) continue;
        orphans.add('[AX-ORPHAN] phase=$phase frame=$frames node ${entry.key} '
            '("${entry.value.label}") wants traversal parent $wanted, '
            'which no node in the tree claims. '
            'owner=${_describeOwner(entry.key)}');
      }
      previous = current;
    }

    WidgetsBinding.instance.addPersistentFrameCallback((_) => checkFrame());

    await runCbFileApp();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Let the video thumbnails generate and land, then recycle the tiles.
    phase = 'video-thumbnails';
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    final labels = previous.values.map((n) => n.label).toList();
    debugPrint('[AX] after thumbnails:'
        ' Image=${find.byType(Image).evaluate().length}'
        ' RawImage=${find.byType(RawImage).evaluate().length}'
        ' LazyVideoThumbnail=${find.byType(LazyVideoThumbnail).evaluate().length}'
        ' ThumbnailLoader=${find.byType(ThumbnailLoader).evaluate().length}'
        ' mp4Labels=${labels.where((l) => l.contains('.mp4')).length}'
        ' txtLabels=${labels.where((l) => l.contains('.txt')).length}'
        ' mp4Finder=${find.textContaining('.mp4').evaluate().length}');

    phase = 'click-row';
    final firstRow = find.textContaining('file_0.txt');
    if (firstRow.evaluate().isEmpty) {
      debugPrint('[AX] click-row skipped: no file_0.txt row on screen');
    } else {
      await tester.tap(firstRow.first);
      await tester.pumpAndSettle();
    }

    phase = 'arrow-keys';
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }

    phase = 'scroll';
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 400));
    await tester.pumpAndSettle();

    phase = 'toggle-drawer-section';
    for (final label in <String>['Drives', 'Pinned']) {
      final header = find.text(label);
      if (header.evaluate().isEmpty) continue;
      await tester.tap(header.first);
      await tester.pumpAndSettle();
      await tester.tap(header.first);
      await tester.pumpAndSettle();
    }

    phase = 'switch-tab';
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    phase = 'ctrl-a';
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    // Tooltips are the prime suspect for "Nodes left pending": an OverlayPortal
    // anchor carries `traversalParentIdentifier`, and the overlay child it owns
    // declares the matching `traversalChildIdentifier`. If the anchor node is
    // merged away, the overlay child is emitted with a traversal parent that is
    // not in the tree and the whole AXTreeUpdate is rejected. Hovering every
    // toolbar button walks that path for real.
    phase = 'hover-tooltips';
    final tooltipAnchors = find.byType(Tooltip);
    debugPrint(
        '[AX] tooltip anchors on screen=${tooltipAnchors.evaluate().length}');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    for (var i = 0; i < tooltipAnchors.evaluate().length && i < 12; i++) {
      final anchor = tooltipAnchors.at(i);
      if (anchor.evaluate().isEmpty) continue;
      try {
        await mouse.moveTo(tester.getCenter(anchor));
      } catch (_) {
        continue;
      }
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 700));
    }
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    await mouse.removePointer();

    debugPrint('[AX] mixed add/remove frames=${mixed.length}');
    for (final line in mixed.take(25)) {
      debugPrint(line);
    }
    debugPrint('[AX] semanticsEnabled='
        '${SemanticsBinding.instance.semanticsEnabled} '
        'nodes=${previous.length} frames=$frames '
        'remounts=${churn.length} orphans=${orphans.length}');
    for (final line in churn.take(40)) {
      debugPrint(line);
    }
    for (final line in orphans.take(40)) {
      debugPrint(line);
    }

    handle.dispose();
    await e2eTearDown(tester, dir);

    expect(
      SemanticsBinding.instance.semanticsEnabled && frames > 10,
      isTrue,
      reason: 'the run must actually have produced semantics frames',
    );
    expect(churn, isEmpty,
        reason: 'semantics nodes were destroyed and recreated unchanged');
    expect(orphans, isEmpty,
        reason: 'an overlay subtree named a traversal parent that is not in '
            'the tree; the Windows AccessibilityBridge drops the whole update');
  });
}
