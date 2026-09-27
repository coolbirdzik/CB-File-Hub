import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as pathlib;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:cb_file_manager/design_system/tokens/cb_geometry_tokens.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import '../widgets/image_viewer_chrome.dart';
import 'crop_view.dart';
import 'edit_model.dart';
import 'edit_renderer.dart';

enum EditorTool { crop, adjust, filters, markup, erase }

enum MarkupTool {
  pen,
  highlighter,
  arrow,
  line,
  rectangle,
  ellipse,
  text,
  eraser,
}

/// Full-screen editor: crop and rotate, tonal adjustments, filters, markup
/// and object erasing, with undo. Saves the result as a new file.
class ImageEditorScreen extends StatefulWidget {
  final File file;

  /// Clockwise quarter turns to start from, e.g. the viewer's rotation.
  final int initialQuarterTurns;
  final VoidCallback onClose;
  final ValueChanged<File>? onSaved;

  const ImageEditorScreen({
    super.key,
    required this.file,
    required this.onClose,
    this.initialQuarterTurns = 0,
    this.onSaved,
  });

  @override
  State<ImageEditorScreen> createState() => ImageEditorScreenState();
}

class _AspectOption {
  final String id;
  final String label;

  /// Width / height; null for a free crop. The 'original' option is
  /// resolved from the picture.
  final double? ratio;

  const _AspectOption(this.id, this.label, this.ratio);
}

class _AdjustmentSpec {
  final String label;
  final IconData icon;
  final double Function(ImageAdjustments a) read;
  final ImageAdjustments Function(ImageAdjustments a, double v) write;
  final double min;

  const _AdjustmentSpec(
    this.label,
    this.icon,
    this.read,
    this.write, {
    this.min = -1,
  });
}

class ImageEditorScreenState extends State<ImageEditorScreen> {
  static const int _maxHistory = 30;
  static const double _maxDecodeSide = 8192;
  static const Color _surface = Color(0xFF0B0B0D);

  static const List<_AspectOption> _aspects = <_AspectOption>[
    _AspectOption('free', 'Free', null),
    _AspectOption('original', 'Original', null),
    _AspectOption('1:1', '1:1', 1),
    _AspectOption('4:3', '4:3', 4 / 3),
    _AspectOption('3:4', '3:4', 3 / 4),
    _AspectOption('3:2', '3:2', 3 / 2),
    _AspectOption('2:3', '2:3', 2 / 3),
    _AspectOption('16:9', '16:9', 16 / 9),
    _AspectOption('9:16', '9:16', 9 / 16),
  ];

  static const Map<String, String> _rotatedAspect = <String, String>{
    '4:3': '3:4',
    '3:4': '4:3',
    '3:2': '2:3',
    '2:3': '3:2',
    '16:9': '9:16',
    '9:16': '16:9',
  };

  static final List<_AdjustmentSpec> _adjustmentSpecs = <_AdjustmentSpec>[
    _AdjustmentSpec(
      'Exposure',
      PhosphorIconsLight.sparkle,
      (a) => a.exposure,
      (a, v) => a.copyWith(exposure: v),
    ),
    _AdjustmentSpec(
      'Brightness',
      PhosphorIconsLight.sun,
      (a) => a.brightness,
      (a, v) => a.copyWith(brightness: v),
    ),
    _AdjustmentSpec(
      'Contrast',
      PhosphorIconsLight.circleHalf,
      (a) => a.contrast,
      (a, v) => a.copyWith(contrast: v),
    ),
    _AdjustmentSpec(
      'Saturation',
      PhosphorIconsLight.drop,
      (a) => a.saturation,
      (a, v) => a.copyWith(saturation: v),
    ),
    _AdjustmentSpec(
      'Warmth',
      PhosphorIconsLight.thermometer,
      (a) => a.warmth,
      (a, v) => a.copyWith(warmth: v),
    ),
    _AdjustmentSpec(
      'Tint',
      PhosphorIconsLight.palette,
      (a) => a.tint,
      (a, v) => a.copyWith(tint: v),
    ),
    _AdjustmentSpec(
      'Vignette',
      PhosphorIconsLight.aperture,
      (a) => a.vignette,
      (a, v) => a.copyWith(vignette: v),
      min: 0,
    ),
  ];

  static const List<Color> _palette = <Color>[
    Color(0xFFFF3B30),
    Color(0xFFFF9500),
    Color(0xFFFFCC00),
    Color(0xFF34C759),
    Color(0xFF30B0C7),
    Color(0xFF0A84FF),
    Color(0xFFAF52DE),
    Color(0xFFFF2D55),
    Color(0xFFFFFFFF),
    Color(0xFF000000),
  ];

  ui.Image? _preview;
  Object? _loadError;
  EditState? _original;
  final List<EditState> _history = <EditState>[];
  int _historyIndex = -1;
  int _savedIndex = 0;
  EditState? _state;

  EditorTool _tool = EditorTool.crop;
  String _aspectId = 'free';
  MarkupTool _markupTool = MarkupTool.pen;
  Color _markupColor = _palette.first;
  double _markupSize = 6;
  double _brushSize = 40;

  final ValueNotifier<Annotation?> _pending = ValueNotifier<Annotation?>(null);
  final ValueNotifier<List<StrokeAnnotation>> _eraseMask =
      ValueNotifier<List<StrokeAnnotation>>(const <StrokeAnnotation>[]);
  final ValueNotifier<Offset?> _cursor = ValueNotifier<Offset?>(null);
  final TransformationController _zoom = TransformationController();
  final Set<int> _pointers = <int>{};
  int? _drawPointer;
  Offset? _textPoint;
  EditorViewport? _viewport;

  bool _erasing = false;
  bool _comparing = false;
  bool _saving = false;

  EditState? get state => _state;
  bool get _canUndo => _historyIndex > 0;
  bool get _canRedo => _historyIndex < _history.length - 1;
  bool get _dirty => _historyIndex != _savedIndex;
  bool get _drawingTool =>
      !_comparing && (_tool == EditorTool.markup || _tool == EditorTool.erase);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pending.dispose();
    _eraseMask.dispose();
    _cursor.dispose();
    _zoom.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final buffer = await ui.ImmutableBuffer.fromFilePath(widget.file.path);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      // Very large pictures are edited at a size the GPU handles well.
      final longest = max(descriptor.width, descriptor.height);
      final scale = longest > _maxDecodeSide ? _maxDecodeSide / longest : 1.0;
      final codec = await descriptor.instantiateCodec(
        targetWidth: scale < 1 ? (descriptor.width * scale).round() : null,
        targetHeight: scale < 1 ? (descriptor.height * scale).round() : null,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      final preview = await createPreview(frame.image);
      if (!mounted) return;
      final original = EditState(image: frame.image);
      final initial = original.copyWith(
        geometry: EditGeometry(
          quarterTurns: ((widget.initialQuarterTurns % 4) + 4) % 4,
        ),
      );
      setState(() {
        _preview = preview;
        _original = original;
        _state = initial;
        _history
          ..clear()
          ..add(initial);
        _historyIndex = 0;
        _savedIndex = 0;
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  // ── History ────────────────────────────────────────────────────────────

  /// Shows [next]; with [commit] it also becomes an undo step. Slider drags
  /// update live and commit once on release.
  void _update(EditState next, {bool commit = true}) {
    setState(() {
      _state = next;
      if (commit) _pushHistory(next);
    });
  }

  void _pushHistory(EditState next) {
    if (_historyIndex >= 0 && identical(_history[_historyIndex], next)) return;
    _history.removeRange(_historyIndex + 1, _history.length);
    _history.add(next);
    if (_history.length > _maxHistory) {
      _history.removeAt(0);
      _savedIndex--;
    }
    _historyIndex = _history.length - 1;
  }

  void _commit() {
    final current = _state;
    if (current == null) return;
    setState(() => _pushHistory(current));
  }

  void _undo() {
    if (!_canUndo) return;
    _cancelDrawing();
    setState(() {
      _historyIndex--;
      _state = _history[_historyIndex];
    });
  }

  void _redo() {
    if (!_canRedo) return;
    _cancelDrawing();
    setState(() {
      _historyIndex++;
      _state = _history[_historyIndex];
    });
  }

  // ── Actions ────────────────────────────────────────────────────────────

  Future<void> _close() async {
    if (_saving) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => _EditorDialog(
          title: 'Discard changes?',
          content: const Text(
            'Your edits have not been saved.',
            style: TextStyle(color: Colors.white70),
          ),
          confirmLabel: 'Discard',
          destructive: true,
        ),
      );
      if (discard != true) return;
    }
    widget.onClose();
  }

  Future<void> _save() async {
    final current = _state;
    if (current == null || _saving || _erasing) return;
    setState(() => _saving = true);
    try {
      final rendered = await renderEdit(current);
      final extension = encodedExtension(pathlib.extension(widget.file.path));
      final bytes = await encodeImage(rendered, extension);
      rendered.dispose();
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Save edited copy',
        fileName:
            '${pathlib.basenameWithoutExtension(widget.file.path)}_edited'
            '$extension',
        bytes: bytes,
        initialDirectory: pathlib.dirname(widget.file.path),
        type: FileType.custom,
        allowedExtensions: <String>[extension.substring(1)],
      );
      if (!mounted || uri == null) return;
      setState(() => _savedIndex = _historyIndex);
      AppToast.success(context, 'Saved edited copy');
      if (uri.scheme == 'file') widget.onSaved?.call(File(uri.toFilePath()));
    } catch (error) {
      if (mounted) AppToast.error(context, 'Unable to save image: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _selectTool(EditorTool tool) {
    if (tool == _tool) return;
    _cancelDrawing();
    _eraseMask.value = const <StrokeAnnotation>[];
    _zoom.value = Matrix4.identity();
    setState(() => _tool = tool);
  }

  void _updateGeometry(EditGeometry Function(EditGeometry g) change) {
    final current = _state;
    if (current == null) return;
    _update(current.copyWith(geometry: change(current.geometry)));
  }

  void _rotate({required bool clockwise}) {
    setState(() => _aspectId = _rotatedAspect[_aspectId] ?? _aspectId);
    _updateGeometry(
      (g) => clockwise ? g.rotatedClockwise() : g.rotatedCounterClockwise(),
    );
  }

  double? _aspectRatio(EditState state) {
    if (_aspectId == 'original') {
      final oriented = state.geometry.orientedSize(state.sourceSize);
      return oriented.width / oriented.height;
    }
    return _aspects.firstWhere((a) => a.id == _aspectId).ratio;
  }

  void _selectAspect(String id) {
    final current = _state;
    if (current == null) return;
    setState(() => _aspectId = id);
    final ratio = _aspectRatio(current);
    if (ratio == null) return;
    // The largest crop of that shape, kept where the current one is.
    final oriented = current.geometry.orientedSize(current.sourceSize);
    final normalizedRatio = ratio * oriented.height / oriented.width;
    var width = 1.0;
    var height = width / normalizedRatio;
    if (height > 1) {
      height = 1;
      width = normalizedRatio;
    }
    final center = current.geometry.crop.center;
    final left = (center.dx - width / 2).clamp(0.0, 1 - width);
    final top = (center.dy - height / 2).clamp(0.0, 1 - height);
    _updateGeometry((g) => g.withCrop(Rect.fromLTWH(left, top, width, height)));
  }

  // ── Drawing ────────────────────────────────────────────────────────────

  double get _viewToSource {
    final viewport = _viewport;
    if (viewport == null) return 1;
    return 1 / (viewport.scale * _zoom.value.getMaxScaleOnAxis());
  }

  void _cancelDrawing() {
    _drawPointer = null;
    _textPoint = null;
    _pending.value = null;
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers.add(event.pointer);
    // A second finger means pinch-zoom, not drawing.
    if (_pointers.length > 1) {
      _cancelDrawing();
      return;
    }
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    final viewport = _viewport;
    final current = _state;
    if (viewport == null || current == null || _erasing) return;
    final point = viewport.toSource(event.localPosition);
    _drawPointer = event.pointer;
    final toSource = _viewToSource;

    if (_tool == EditorTool.erase) {
      _pending.value = StrokeAnnotation(
        points: <Offset>[point],
        color: const Color(0xFFFF3B5C),
        width: _brushSize * toSource,
      );
      return;
    }
    final width = _markupSize * toSource;
    _pending.value = switch (_markupTool) {
      MarkupTool.pen => StrokeAnnotation(
        points: <Offset>[point],
        color: _markupColor,
        width: width,
      ),
      MarkupTool.highlighter => StrokeAnnotation(
        points: <Offset>[point],
        color: _markupColor,
        width: width * 3.5,
        kind: StrokeKind.highlighter,
      ),
      MarkupTool.eraser => StrokeAnnotation(
        points: <Offset>[point],
        color: _markupColor,
        width: width * 4,
        kind: StrokeKind.eraser,
      ),
      MarkupTool.arrow ||
      MarkupTool.line ||
      MarkupTool.rectangle ||
      MarkupTool.ellipse => ShapeAnnotation(
        kind: switch (_markupTool) {
          MarkupTool.arrow => ShapeKind.arrow,
          MarkupTool.line => ShapeKind.line,
          MarkupTool.rectangle => ShapeKind.rectangle,
          _ => ShapeKind.ellipse,
        },
        start: point,
        end: point,
        color: _markupColor,
        width: width,
      ),
      MarkupTool.text => null,
    };
    if (_markupTool == MarkupTool.text) _textPoint = point;
  }

  void _onPointerMove(PointerMoveEvent event) {
    _cursor.value = event.localPosition;
    if (event.pointer != _drawPointer) return;
    final viewport = _viewport;
    if (viewport == null) return;
    final point = viewport.toSource(event.localPosition);
    final pending = _pending.value;
    if (pending is StrokeAnnotation) {
      if ((pending.points.last - point).distance < _viewToSource) return;
      _pending.value = pending.withPoint(point);
    } else if (pending is ShapeAnnotation) {
      _pending.value = pending.withEnd(point);
    }
  }

  void _onPointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (event.pointer != _drawPointer) return;
    _drawPointer = null;
    final pending = _pending.value;
    final textPoint = _textPoint;
    _pending.value = null;
    _textPoint = null;
    final current = _state;
    if (current == null) return;

    if (_tool == EditorTool.erase) {
      if (pending is StrokeAnnotation) {
        _eraseMask.value = <StrokeAnnotation>[..._eraseMask.value, pending];
        _applyErase();
      }
      return;
    }
    if (textPoint != null) {
      _addText(textPoint);
      return;
    }
    if (pending is ShapeAnnotation &&
        (pending.end - pending.start).distance < 2 * _viewToSource) {
      return;
    }
    if (pending != null) {
      _update(
        current.copyWith(
          annotations: <Annotation>[...current.annotations, pending],
        ),
      );
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    if (event.pointer == _drawPointer) _cancelDrawing();
  }

  Future<void> _applyErase() async {
    final current = _state;
    final strokes = _eraseMask.value;
    if (current == null || strokes.isEmpty) return;
    setState(() => _erasing = true);
    try {
      final image = await eraseArea(current.image, strokes);
      if (!mounted) return;
      _update(_state!.copyWith(image: image));
    } catch (error) {
      if (mounted) AppToast.error(context, 'Unable to erase: $error');
    } finally {
      _eraseMask.value = const <StrokeAnnotation>[];
      if (mounted) setState(() => _erasing = false);
    }
  }

  Future<void> _addText(Offset point) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => _EditorDialog(
        title: 'Add text',
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          style: const TextStyle(color: Colors.white),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            hintText: 'Type something',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.2),
              ),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white),
            ),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        confirmLabel: 'Add',
        confirmValue: () => controller.text,
      ),
    );
    controller.dispose();
    final current = _state;
    if (!mounted || current == null || text == null || text.trim().isEmpty) {
      return;
    }
    _update(
      current.copyWith(
        annotations: <Annotation>[
          ...current.annotations,
          TextAnnotation(
            anchor: point,
            text: text.trim(),
            color: _markupColor,
            fontSize: (_markupSize * 3 + 16) * _viewToSource,
            quarterTurns: current.geometry.quarterTurns,
            flipped: current.geometry.flipped,
          ),
        ],
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final control =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (key == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    if (control && key == LogicalKeyboardKey.keyZ) {
      shift ? _redo() : _undo();
      return KeyEventResult.handled;
    }
    if (control && key == LogicalKeyboardKey.keyY) {
      _redo();
      return KeyEventResult.handled;
    }
    if (control && key == LogicalKeyboardKey.keyS) {
      _save();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Layout ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: ColoredBox(
        color: _surface,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              if (wide) {
                return Column(
                  children: [
                    _buildTopBar(),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(child: _buildCanvasArea()),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(0, 4, 16, 16),
                            child: SizedBox(
                              width: 340,
                              child: ViewerGlass(
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(20),
                                ),
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: _buildToolTabs(),
                                    ),
                                    Divider(
                                      height: 1,
                                      color: Colors.white.withValues(
                                        alpha: 0.08,
                                      ),
                                    ),
                                    Expanded(
                                      child: SingleChildScrollView(
                                        padding: const EdgeInsets.fromLTRB(
                                          16,
                                          16,
                                          16,
                                          20,
                                        ),
                                        child: _buildOptions(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  _buildTopBar(),
                  Expanded(child: _buildCanvasArea()),
                  AnimatedSize(
                    duration: ViewerMotion.medium,
                    curve: ViewerMotion.curve,
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight * 0.34,
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: _buildOptions(),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: _buildToolTabs(),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final loaded = _state != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      child: Row(
        children: [
          ViewerIconButton(
            icon: PhosphorIconsLight.x,
            tooltip: 'Close editor (Esc)',
            onPressed: _close,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Edit',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  pathlib.basename(widget.file.path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          ViewerIconButton(
            icon: PhosphorIconsLight.arrowUUpLeft,
            tooltip: 'Undo (Ctrl+Z)',
            onPressed: _canUndo && !_erasing ? _undo : null,
          ),
          ViewerIconButton(
            icon: PhosphorIconsLight.arrowUUpRight,
            tooltip: 'Redo (Ctrl+Y)',
            onPressed: _canRedo && !_erasing ? _redo : null,
          ),
          Listener(
            onPointerDown: (_) {
              if (loaded) setState(() => _comparing = true);
            },
            onPointerUp: (_) => setState(() => _comparing = false),
            onPointerCancel: (_) => setState(() => _comparing = false),
            child: ViewerIconButton(
              icon: PhosphorIconsLight.squareHalf,
              tooltip: 'Hold to compare',
              active: _comparing,
              onPressed: loaded ? () {} : null,
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: loaded && !_saving && !_erasing ? _save : null,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.2),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            icon: AnimatedSwitcher(
              duration: ViewerMotion.fast,
              child: _saving
                  ? const SizedBox(
                      key: ValueKey<String>('saving'),
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black54,
                      ),
                    )
                  : const Icon(
                      PhosphorIconsLight.floppyDisk,
                      key: ValueKey<String>('save'),
                      size: 18,
                    ),
            ),
            label: Text(_saving ? 'Saving...' : 'Save copy'),
          ),
        ],
      ),
    );
  }

  Widget _buildToolTabs() {
    const tabs = <(EditorTool, IconData, String)>[
      (EditorTool.crop, PhosphorIconsLight.crop, 'Crop'),
      (EditorTool.adjust, PhosphorIconsLight.slidersHorizontal, 'Adjust'),
      (EditorTool.filters, PhosphorIconsLight.magicWand, 'Filters'),
      (EditorTool.markup, PhosphorIconsLight.pencilSimple, 'Markup'),
      (EditorTool.erase, PhosphorIconsLight.eraser, 'Erase'),
    ];
    return Row(
      children: [
        for (final (tool, icon, label) in tabs)
          Expanded(
            child: _ToolTab(
              icon: icon,
              label: label,
              selected: _tool == tool,
              onTap: _state == null ? null : () => _selectTool(tool),
            ),
          ),
      ],
    );
  }

  Widget _buildOptions() {
    final current = _state;
    final Widget options;
    if (current == null) {
      options = const SizedBox(key: ValueKey<String>('none'), height: 60);
    } else {
      options = KeyedSubtree(
        key: ValueKey<EditorTool>(_tool),
        child: switch (_tool) {
          EditorTool.crop => _buildCropOptions(current),
          EditorTool.adjust => _buildAdjustOptions(current),
          EditorTool.filters => _buildFilterOptions(current),
          EditorTool.markup => _buildMarkupOptions(),
          EditorTool.erase => _buildEraseOptions(),
        },
      );
    }
    return AnimatedSwitcher(
      duration: ViewerMotion.medium,
      switchInCurve: ViewerMotion.curve,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: options,
    );
  }

  Widget _buildCropOptions(EditState current) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SectionLabel('Aspect ratio'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final aspect in _aspects)
              _EditorChip(
                label: aspect.label,
                selected: _aspectId == aspect.id,
                onTap: () => _selectAspect(aspect.id),
              ),
          ],
        ),
        const SizedBox(height: 14),
        const _SectionLabel('Rotate & flip'),
        Row(
          children: [
            ViewerIconButton(
              icon: PhosphorIconsLight.arrowCounterClockwise,
              tooltip: 'Rotate left',
              onPressed: () => _rotate(clockwise: false),
            ),
            ViewerIconButton(
              icon: PhosphorIconsLight.arrowClockwise,
              tooltip: 'Rotate right',
              onPressed: () => _rotate(clockwise: true),
            ),
            ViewerIconButton(
              icon: PhosphorIconsLight.flipHorizontal,
              tooltip: 'Flip horizontal',
              onPressed: () => _updateGeometry((g) => g.flippedHorizontally()),
            ),
            ViewerIconButton(
              icon: PhosphorIconsLight.flipVertical,
              tooltip: 'Flip vertical',
              onPressed: () => _updateGeometry((g) => g.flippedVertically()),
            ),
            const Spacer(),
            _ResetButton(
              enabled: !current.geometry.isIdentity || _aspectId != 'free',
              onPressed: () {
                setState(() => _aspectId = 'free');
                _updateGeometry((_) => const EditGeometry());
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAdjustOptions(EditState current) {
    final adjustments = current.adjustments;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionLabel('Light & colour')),
            _ResetButton(
              enabled: !adjustments.isIdentity,
              onPressed: () => _update(
                current.copyWith(adjustments: const ImageAdjustments()),
              ),
            ),
          ],
        ),
        for (final spec in _adjustmentSpecs)
          _EditorSlider(
            label: spec.label,
            icon: spec.icon,
            value: spec.read(adjustments),
            min: spec.min,
            max: 1,
            onChanged: (value) => _update(
              _state!.copyWith(
                adjustments: spec.write(_state!.adjustments, value),
              ),
              commit: false,
            ),
            onChangeEnd: (_) => _commit(),
            onReset: () => _update(
              _state!.copyWith(adjustments: spec.write(_state!.adjustments, 0)),
            ),
          ),
      ],
    );
  }

  Widget _buildFilterOptions(EditState current) {
    final preview = _preview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SectionLabel('Filters'),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: ImageFilterPreset.all.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final preset = ImageFilterPreset.all[index];
              return _FilterTile(
                preset: preset,
                preview: preview,
                selected: current.filterId == preset.id,
                onTap: () => _update(
                  current.copyWith(filterId: preset.id, filterStrength: 1),
                ),
              );
            },
          ),
        ),
        AnimatedSize(
          duration: ViewerMotion.medium,
          curve: ViewerMotion.curve,
          child: current.filterId == 'none'
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _EditorSlider(
                    label: 'Strength',
                    icon: PhosphorIconsLight.circleHalf,
                    value: current.filterStrength,
                    min: 0,
                    max: 1,
                    onChanged: (value) => _update(
                      _state!.copyWith(filterStrength: value),
                      commit: false,
                    ),
                    onChangeEnd: (_) => _commit(),
                    onReset: () => _update(_state!.copyWith(filterStrength: 1)),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildMarkupOptions() {
    const tools = <(MarkupTool, IconData, String)>[
      (MarkupTool.pen, PhosphorIconsLight.pencilSimple, 'Pen'),
      (MarkupTool.highlighter, PhosphorIconsLight.highlighter, 'Highlighter'),
      (MarkupTool.arrow, PhosphorIconsLight.arrowUpRight, 'Arrow'),
      (MarkupTool.line, PhosphorIconsLight.lineSegment, 'Line'),
      (MarkupTool.rectangle, PhosphorIconsLight.square, 'Rectangle'),
      (MarkupTool.ellipse, PhosphorIconsLight.circle, 'Ellipse'),
      (MarkupTool.text, PhosphorIconsLight.textT, 'Text'),
      (MarkupTool.eraser, PhosphorIconsLight.eraser, 'Erase markup'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SectionLabel('Tool'),
        Wrap(
          spacing: 2,
          runSpacing: 2,
          children: [
            for (final (tool, icon, label) in tools)
              ViewerIconButton(
                icon: icon,
                tooltip: label,
                active: _markupTool == tool,
                onPressed: () => setState(() => _markupTool = tool),
              ),
          ],
        ),
        const SizedBox(height: 12),
        AnimatedOpacity(
          opacity: _markupTool == MarkupTool.eraser ? 0.35 : 1,
          duration: ViewerMotion.fast,
          child: IgnorePointer(
            ignoring: _markupTool == MarkupTool.eraser,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionLabel('Colour'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final color in _palette)
                      _ColorSwatch(
                        color: color,
                        selected: _markupColor == color,
                        onTap: () => setState(() => _markupColor = color),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _EditorSlider(
          label: _markupTool == MarkupTool.text ? 'Text size' : 'Size',
          icon: PhosphorIconsLight.circle,
          value: _markupSize,
          min: 2,
          max: 40,
          format: (value) => value.round().toString(),
          onChanged: (value) => setState(() => _markupSize = value),
          onReset: () => setState(() => _markupSize = 6),
        ),
        AnimatedSwitcher(
          duration: ViewerMotion.medium,
          child: _markupTool == MarkupTool.text
              ? const _Hint(
                  key: ValueKey<String>('text-hint'),
                  text: 'Click on the picture where the text should go.',
                )
              : const SizedBox.shrink(key: ValueKey<String>('no-hint')),
        ),
      ],
    );
  }

  Widget _buildEraseOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SectionLabel('Erase'),
        const _Hint(
          text:
              'Paint over what you want to remove. It is filled in from '
              'its surroundings. Works best on small objects and blemishes.',
        ),
        const SizedBox(height: 8),
        _EditorSlider(
          label: 'Brush',
          icon: PhosphorIconsLight.paintBrush,
          value: _brushSize,
          min: 8,
          max: 160,
          format: (value) => value.round().toString(),
          onChanged: (value) => setState(() => _brushSize = value),
          onReset: () => setState(() => _brushSize = 40),
        ),
      ],
    );
  }

  Widget _buildCanvasArea() {
    final current = _state;
    final Widget child;
    if (_loadError != null) {
      child = Center(
        key: const ValueKey<String>('error'),
        child: Text(
          'Unable to open this image for editing.\n$_loadError',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    } else if (current == null) {
      child = const Center(
        key: ValueKey<String>('loading'),
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: Colors.white60,
          ),
        ),
      );
    } else if (_tool == EditorTool.crop && !_comparing) {
      child = CropView(
        key: const ValueKey<String>('crop'),
        state: current,
        aspectRatio: _aspectRatio(current),
        onChanged: (crop) => _update(
          _state!.copyWith(geometry: _state!.geometry.withCrop(crop)),
          commit: false,
        ),
        onChangeEnd: _commit,
      );
    } else {
      child = KeyedSubtree(
        key: const ValueKey<String>('preview'),
        child: _buildPreview(_comparing ? _original! : current),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: ViewerMotion.medium,
          switchInCurve: ViewerMotion.curve,
          child: child,
        ),
        Positioned(
          top: 8,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: AnimatedOpacity(
                opacity: _comparing || _erasing ? 1 : 0,
                duration: ViewerMotion.fast,
                child: ViewerGlass(
                  borderRadius: const BorderRadius.all(Radius.circular(14)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_erasing) ...[
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.6,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        _erasing ? 'Erasing...' : 'Original',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreview(EditState shown) {
    final drawing = _drawingTool;
    final erasing = _tool == EditorTool.erase;
    final showBrush = drawing && (erasing || _markupTool == MarkupTool.eraser);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final viewport = EditorViewport.fit(
          size,
          shown,
          padding: const EdgeInsets.all(24),
        );
        _viewport = viewport;
        final brushDiameter = !showBrush
            ? 0.0
            : (erasing ? _brushSize : _markupSize * 4);
        return ClipRect(
          child: InteractiveViewer(
            transformationController: _zoom,
            minScale: 1,
            maxScale: 8,
            panEnabled: !drawing,
            child: SizedBox.fromSize(
              size: size,
              child: Listener(
                onPointerDown: drawing ? _onPointerDown : null,
                onPointerMove: drawing ? _onPointerMove : null,
                onPointerUp: drawing ? _onPointerUp : null,
                onPointerCancel: drawing ? _onPointerCancel : null,
                child: MouseRegion(
                  cursor: drawing
                      ? (showBrush
                            ? SystemMouseCursors.none
                            : SystemMouseCursors.precise)
                      : MouseCursor.defer,
                  onHover: (event) => _cursor.value = event.localPosition,
                  onExit: (_) => _cursor.value = null,
                  child: AnimatedBuilder(
                    animation: _zoom,
                    builder: (context, _) => CustomPaint(
                      painter: _EditPainter(
                        state: shown,
                        viewport: viewport,
                        pending: _pending,
                        eraseMask: _eraseMask,
                        cursor: _cursor,
                        maskMode: erasing,
                        brushRadius:
                            brushDiameter / 2 / _zoom.value.getMaxScaleOnAxis(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EditPainter extends CustomPainter {
  final EditState state;
  final EditorViewport viewport;
  final ValueNotifier<Annotation?> pending;
  final ValueNotifier<List<StrokeAnnotation>> eraseMask;
  final ValueNotifier<Offset?> cursor;
  final bool maskMode;
  final double brushRadius;

  _EditPainter({
    required this.state,
    required this.viewport,
    required this.pending,
    required this.eraseMask,
    required this.cursor,
    required this.maskMode,
    required this.brushRadius,
  }) : super(
         repaint: Listenable.merge(<Listenable>[pending, eraseMask, cursor]),
       );

  @override
  void paint(Canvas canvas, Size size) {
    final frame = viewport.frame;
    canvas.drawRect(
      frame.shift(const Offset(0, 6)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    final current = pending.value;
    paintEdit(
      canvas,
      state,
      sourceToView: viewport.sourceToView,
      frame: frame,
      clip: frame,
      pending: maskMode ? null : current,
      eraseMask: maskMode && current is StrokeAnnotation
          ? <StrokeAnnotation>[...eraseMask.value, current]
          : eraseMask.value,
    );

    final position = cursor.value;
    if (position != null && brushRadius > 0) {
      canvas.drawCircle(
        position,
        brushRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white,
      );
      canvas.drawCircle(
        position,
        brushRadius + 1,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = Colors.black54,
      );
    }
  }

  @override
  bool shouldRepaint(_EditPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.viewport.sourceToView != viewport.sourceToView ||
      oldDelegate.viewport.frame != viewport.frame ||
      oldDelegate.maskMode != maskMode ||
      oldDelegate.brushRadius != brushRadius;
}

class _ToolTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _ToolTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Colors.white
        : Colors.white.withValues(alpha: onTap == null ? 0.3 : 0.6);
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: ViewerMotion.medium,
            curve: ViewerMotion.curve,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: selected ? 1.12 : 1,
                  duration: ViewerMotion.medium,
                  curve: ViewerMotion.curve,
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(height: 4),
                AnimatedDefaultTextStyle(
                  duration: ViewerMotion.medium,
                  style: TextStyle(
                    color: color,
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                  child: Text(label, maxLines: 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.45),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;

  const _Hint({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.6),
          fontSize: 12.5,
          height: 1.4,
        ),
      ),
    );
  }
}

class _ResetButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPressed;

  const _ResetButton({required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: enabled ? 1 : 0.35,
      duration: ViewerMotion.fast,
      child: TextButton.icon(
        onPressed: enabled ? onPressed : null,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          visualDensity: VisualDensity.compact,
        ),
        icon: const Icon(PhosphorIconsLight.arrowsClockwise, size: 16),
        label: const Text('Reset'),
      ),
    );
  }
}

class _EditorChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _EditorChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: ViewerMotion.medium,
          curve: ViewerMotion.curve,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.08),
            // Soft rounded rect, matching every other button in the app.
            borderRadius: CbRadii.buttonAll,
          ),
          child: AnimatedDefaultTextStyle(
            duration: ViewerMotion.medium,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedScale(
          scale: selected ? 1.15 : 1,
          duration: ViewerMotion.medium,
          curve: ViewerMotion.curve,
          child: AnimatedContainer(
            duration: ViewerMotion.medium,
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.2),
                width: selected ? 2.5 : 1,
              ),
              boxShadow: selected
                  ? <BoxShadow>[
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ]
                  : const <BoxShadow>[],
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorSlider extends StatelessWidget {
  final String label;
  final IconData icon;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final VoidCallback onReset;
  final String Function(double value)? format;

  const _EditorSlider({
    required this.label,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onReset,
    this.onChangeEnd,
    this.format,
  });

  String get _valueText {
    if (format != null) return format!(value);
    final percent = (value * 100).round();
    return percent > 0 ? '+$percent' : '$percent';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.white70),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: 'Double-click to reset',
                  waitDuration: const Duration(milliseconds: 800),
                  child: GestureDetector(
                    onDoubleTap: onReset,
                    child: Text(
                      label,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              ),
              Text(
                _valueText,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.16),
              thumbColor: Colors.white,
              overlayColor: Colors.white.withValues(alpha: 0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Semantics(
              label: label,
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterTile extends StatelessWidget {
  final ImageFilterPreset preset;
  final ui.Image? preview;
  final bool selected;
  final VoidCallback onTap;

  const _FilterTile({
    required this.preset,
    required this.preview,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const size = 72.0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            AnimatedScale(
              scale: selected ? 1.0 : 0.94,
              duration: ViewerMotion.medium,
              curve: ViewerMotion.curve,
              child: AnimatedContainer(
                duration: ViewerMotion.medium,
                curve: ViewerMotion.curve,
                width: size,
                height: size,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: preview == null
                      ? ColoredBox(color: Colors.white.withValues(alpha: 0.08))
                      : CustomPaint(
                          painter: _FilterPreviewPainter(
                            preview!,
                            preset.matrix,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            AnimatedDefaultTextStyle(
              duration: ViewerMotion.medium,
              style: TextStyle(
                color: selected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.6),
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
              child: Text(preset.name),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterPreviewPainter extends CustomPainter {
  final ui.Image image;
  final List<double> matrix;

  _FilterPreviewPainter(this.image, this.matrix);

  @override
  void paint(Canvas canvas, Size size) {
    // Centre-crop to fill the square.
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final fitted = applyBoxFit(BoxFit.cover, imageSize, size);
    final source = Alignment.center.inscribe(
      fitted.source,
      Offset.zero & imageSize,
    );
    canvas.drawImageRect(
      image,
      source,
      Offset.zero & size,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..colorFilter = ColorFilter.matrix(matrix),
    );
  }

  @override
  bool shouldRepaint(_FilterPreviewPainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.matrix != matrix;
}

/// Small dark confirmation dialog matching the editor.
class _EditorDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final String confirmLabel;
  final bool destructive;

  /// Value popped by the confirm button; `true` when null.
  final Object? Function()? confirmValue;

  const _EditorDialog({
    required this.title,
    required this.content,
    required this.confirmLabel,
    this.destructive = false,
    this.confirmValue,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1C1C20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: content,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: Colors.white70),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(confirmValue?.call() ?? true),
          style: FilledButton.styleFrom(
            backgroundColor: destructive
                ? const Color(0xFFFF453A)
                : Colors.white,
            foregroundColor: destructive ? Colors.white : Colors.black,
          ),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
