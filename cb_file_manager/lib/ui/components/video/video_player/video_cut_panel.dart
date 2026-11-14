import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/translation_helper.dart';
import '../../../../design_system/cb_design_system.dart';
import '../../../../services/media/lossless_cut_service.dart';
import '../../../utils/video_output_folder_navigation.dart';
import 'video_cut_export_location.dart';

/// Embedded below the video: the playback surface remains mounted while editing.
class VideoCutPanel extends StatefulWidget {
  final String source;
  final Duration duration;
  final Duration Function() position;
  final ValueChanged<Duration> onSeek;
  final VoidCallback? onRangeSeekStart;
  final ValueChanged<Duration>? onRangeSeek;
  final ValueChanged<Duration>? onRangeSeekEnd;
  final VoidCallback onClose;

  const VideoCutPanel({
    super.key,
    required this.source,
    required this.duration,
    required this.position,
    required this.onSeek,
    this.onRangeSeekStart,
    this.onRangeSeek,
    this.onRangeSeekEnd,
    required this.onClose,
  });

  @override
  State<VideoCutPanel> createState() => VideoCutPanelState();
}

class VideoCutPanelState extends State<VideoCutPanel> {
  final _service = LosslessCutService();
  final _startText = TextEditingController();
  final _endText = TextEditingController();
  final _segments = <VideoCutSegment>[];
  final _segmentsScrollController = ScrollController();
  int _selectedSegment = 0;
  Duration? _rangeSeekPosition;
  RangeValues? _previousRangeValues;
  bool _draggingRangeEnd = false;
  late Duration _end = widget.duration;
  Duration _start = Duration.zero;
  String? _executable;
  String? _error;
  List<String> _outputs = [];
  bool _merge = false;
  bool _includeSubtitles = false;
  bool _showExportOptions = false;
  final _optionsKey = GlobalKey();
  VideoCutTimestampMode _timestampMode = VideoCutTimestampMode.exportTime;
  String _container = 'source';
  bool _busy = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _segments.add(VideoCutSegment(_start, _end));
    _syncFields();
    LosslessCutService.findExecutable().then((value) {
      if (mounted) setState(() => _executable ??= value);
    });
  }

  @override
  void dispose() {
    _service.cancel();
    _startText.dispose();
    _endText.dispose();
    _segmentsScrollController.dispose();
    super.dispose();
  }

  static String timecode(Duration value) {
    final ms = value.inMilliseconds;
    return '${(ms ~/ 3600000).toString().padLeft(2, '0')}:'
        '${(ms ~/ 60000 % 60).toString().padLeft(2, '0')}:'
        '${(ms ~/ 1000 % 60).toString().padLeft(2, '0')}.'
        '${(ms % 1000).toString().padLeft(3, '0')}';
  }

  static Duration? parseTimecode(String value) {
    final match = RegExp(
      r'^(\d{1,6}):([0-5]\d):([0-5]\d)(?:\.(\d{1,3}))?$',
    ).firstMatch(value.trim());
    if (match == null) return null;
    return Duration(
      hours: int.parse(match[1]!),
      minutes: int.parse(match[2]!),
      seconds: int.parse(match[3]!),
      milliseconds: int.parse((match[4] ?? '').padRight(3, '0')),
    );
  }

  void _syncFields() {
    _startText.text = timecode(_start);
    _endText.text = timecode(_end);
  }

  void markIn() {
    if (_busy) return;
    setState(() {
      _start = widget.position().clampTo(widget.duration);
      if (_end <= _start) _end = widget.duration;
      _syncFields();
      _saveSegment();
    });
  }

  void markOut() {
    if (_busy) return;
    setState(() {
      _end = widget.position().clampTo(widget.duration);
      if (_start >= _end) _start = Duration.zero;
      _syncFields();
      _saveSegment();
    });
  }

  VideoCutSegment? _readDraft() {
    final start = parseTimecode(_startText.text);
    final end = parseTimecode(_endText.text);
    if (start == null ||
        end == null ||
        !VideoCutSegment(start, end).isValidFor(widget.duration)) {
      setState(() => _error = context.tr.cutInvalidRange);
      return null;
    }
    _start = start;
    _end = end;
    _saveSegment();
    return VideoCutSegment(start, end);
  }

  void _saveSegment() {
    _segments[_selectedSegment] = VideoCutSegment(_start, _end);
  }

  void _timecodeChanged(String _) {
    final start = parseTimecode(_startText.text);
    final end = parseTimecode(_endText.text);
    if (start == null ||
        end == null ||
        !VideoCutSegment(start, end).isValidFor(widget.duration)) {
      return;
    }
    setState(() {
      _start = start;
      _end = end;
      _error = null;
      _saveSegment();
    });
  }

  void _changeRange(RangeValues value) {
    final start = Duration(milliseconds: value.start.round());
    final end = Duration(milliseconds: value.end.round());
    // Track unrounded slider values so tiny/repeated pointer moves cannot
    // switch the active boundary after converting to milliseconds.
    final previous =
        _previousRangeValues ??
        RangeValues(
          _start.inMilliseconds.toDouble(),
          _end.inMilliseconds.toDouble(),
        );
    if (value.start != previous.start) {
      _draggingRangeEnd = false;
    } else if (value.end != previous.end) {
      _draggingRangeEnd = true;
    }
    _previousRangeValues = value;
    final target = _draggingRangeEnd ? end : start;
    setState(() {
      _start = start;
      _end = end;
      _rangeSeekPosition = target;
      _error = null;
      _syncFields();
      _saveSegment();
    });
    (widget.onRangeSeek ?? widget.onSeek)(target);
  }

  void _selectSegment(int index) {
    if (_readDraft() == null) return;
    setState(() {
      _selectedSegment = index;
      _start = _segments[index].start;
      _end = _segments[index].end;
      _error = null;
      _syncFields();
    });
    widget.onSeek(_start);
  }

  void _removeSegment(int index) {
    if (_segments.length <= 1) return;
    setState(() {
      _segments.removeAt(index);
      if (index < _selectedSegment || _selectedSegment == _segments.length) {
        _selectedSegment--;
      }
      _start = _segments[_selectedSegment].start;
      _end = _segments[_selectedSegment].end;
      _error = null;
      _syncFields();
    });
  }

  void _addSegment() {
    final draft = _readDraft();
    if (draft == null) return;
    setState(() {
      _start = draft.end < widget.duration ? draft.end : Duration.zero;
      _end = widget.duration;
      _segments.add(VideoCutSegment(_start, _end));
      _selectedSegment = _segments.length - 1;
      _error = null;
      _syncFields();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _segmentsScrollController.hasClients) {
        _segmentsScrollController.animateTo(
          _segmentsScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
    widget.onSeek(_start);
  }

  Future<void> _chooseExecutable() async {
    try {
      final selection = await FilePicker.pickFiles(
        dialogTitle: context.tr.cutChooseFfmpeg,
      );
      if (!mounted) return;
      final path = selection.isEmpty ? null : selection.single.path;
      if (path != null) setState(() => _executable = path);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _export() async {
    if (_readDraft() == null) return;
    final segments = List<VideoCutSegment>.of(_segments);
    if (segments.any((segment) => !segment.isValidFor(widget.duration))) {
      setState(() => _error = context.tr.cutInvalidRange);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _outputs = [];
      _progress = 0;
    });
    try {
      final location = await chooseVideoCutExportLocation(
        context,
        widget.source,
      );
      if (!mounted || location == null) return;
      final inPlace = location == VideoCutExportLocation.besideSource;
      final destination = inPlace
          ? p.dirname(p.absolute(widget.source))
          : await FilePicker.getDirectoryPath(
              dialogTitle: context.tr.cutOutputFolder,
            );
      if (!mounted || destination == null) return;
      final outputs = await _service.export(
        executable: _executable!,
        input: widget.source,
        destination: destination,
        createSubfolder: !inPlace,
        duration: widget.duration,
        segments: segments,
        merge: _merge,
        includeSubtitles: _includeSubtitles,
        timestampMode: _timestampMode,
        container: _container == 'source' ? null : _container,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      if (mounted) setState(() => _outputs = outputs);
    } on LosslessCutCancelled {
      // Cancellation removes this export's partial files in the service.
    } catch (error) {
      if (mounted) {
        setState(() => _error = '${context.tr.cutExportFailed}\n$error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openOutput() async {
    try {
      await openVideoOutputFolderInApp(
        context,
        p.dirname(_outputs.first),
        highlightedFileName: p.basename(_outputs.first),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Widget _rangeEditor(BuildContext context, {bool compactTimecodes = false}) {
    final tr = context.tr;
    final colors = context.cb.colors;
    final maxMs = widget.duration.inMilliseconds.toDouble();
    final markInControl = CbButton(
      label: 'I',
      tooltip: tr.cutMarkIn,
      size: CbButtonSize.xs,
      variant: CbButtonVariant.ghost,
      onPressed: _busy ? null : markIn,
    );
    final markOutControl = CbButton(
      label: 'O',
      tooltip: tr.cutMarkOut,
      size: CbButtonSize.xs,
      variant: CbButtonVariant.ghost,
      onPressed: _busy ? null : markOut,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                tr.cutRange,
                style: CbTypography.labelSm,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (compactTimecodes) ...[
              markInControl,
              markOutControl,
            ] else
              Text(
                timecode(_end - _start),
                style: CbTypography.monoSm.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            const SizedBox(width: 8),
            CbButton.icon(
              icon: PhosphorIconsLight.play,
              tooltip: tr.cutPreview,
              size: CbButtonSize.sm,
              onPressed: _busy
                  ? null
                  : () {
                      final draft = _readDraft();
                      if (draft != null) widget.onSeek(draft.start);
                    },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: CbTextField(
                controller: _startText,
                mono: true,
                label: tr.cutStart,
                enabled: !_busy,
                onChanged: _timecodeChanged,
                suffix: compactTimecodes ? null : markInControl,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CbTextField(
                controller: _endText,
                mono: true,
                label: tr.cutEnd,
                enabled: !_busy,
                onChanged: _timecodeChanged,
                suffix: compactTimecodes ? null : markOutControl,
              ),
            ),
          ],
        ),
        if (maxMs > 0)
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              rangeThumbShape: const RoundRangeSliderThumbShape(
                enabledThumbRadius: 6,
              ),
            ),
            child: Semantics(
              container: true,
              label: tr.cutRange,
              child: Overlay.wrap(
                alwaysSizeToContent: true,
                child: RangeSlider(
                  values: RangeValues(
                    _start.inMilliseconds.toDouble().clamp(0, maxMs),
                    _end.inMilliseconds.toDouble().clamp(0, maxMs),
                  ),
                  max: maxMs,
                  semanticFormatterCallback: (value) =>
                      timecode(Duration(milliseconds: value.round())),
                  onChangeStart: _busy
                      ? null
                      : (value) {
                          _rangeSeekPosition = null;
                          _previousRangeValues = value;
                          _draggingRangeEnd = false;
                          widget.onRangeSeekStart?.call();
                        },
                  onChanged: _busy ? null : _changeRange,
                  onChangeEnd: _busy
                      ? null
                      : (_) {
                          _previousRangeValues = null;
                          (widget.onRangeSeekEnd ?? widget.onSeek)(
                            _rangeSeekPosition ??
                                widget.position().clampTo(widget.duration),
                          );
                        },
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _segmentList(BuildContext context) {
    final tr = context.tr;
    final colors = context.cb.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${tr.cutSegments} (${_segments.length})',
                style: CbTypography.labelSm,
              ),
            ),
            CbButton(
              label: tr.cutAddSegment,
              icon: PhosphorIconsLight.plus,
              size: CbButtonSize.sm,
              variant: CbButtonVariant.ghost,
              onPressed: _busy ? null : _addSegment,
            ),
          ],
        ),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 144),
          child: SingleChildScrollView(
            controller: _segmentsScrollController,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _segments.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            selected: i == _selectedSegment,
                            child: CbPressable(
                              key: ValueKey('cut-segment-$i'),
                              semanticLabel:
                                  '${LosslessCutService.segmentFileName(widget.source, i + 1, container: _container == 'source' ? null : _container)}, '
                                  '${timecode(_segments[i].start)} – ${timecode(_segments[i].end)}',
                              onPressed: _busy ? null : () => _selectSegment(i),
                              enabled: !_busy,
                              builder: (context, interaction) => AnimatedContainer(
                                duration: const Duration(milliseconds: 100),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: interaction.pressed
                                      ? colors.surfacePressed
                                      : interaction.hovered
                                      ? colors.surfaceHover
                                      : i == _selectedSegment
                                      ? colors.surfaceSelected
                                      : colors.fillSubtle,
                                  borderRadius: BorderRadius.circular(
                                    CbRadii.md,
                                  ),
                                  border: interaction.focused
                                      ? Border.all(
                                          color: colors.focusRing,
                                          width: 2,
                                        )
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      '${i + 1}'.padLeft(2, '0'),
                                      style: CbTypography.monoSm.copyWith(
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            LosslessCutService.segmentFileName(
                                              widget.source,
                                              i + 1,
                                              container: _container == 'source'
                                                  ? null
                                                  : _container,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: CbTypography.labelSm,
                                          ),
                                          Text(
                                            '${timecode(_segments[i].start)} – ${timecode(_segments[i].end)}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: CbTypography.monoSm.copyWith(
                                              color: colors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        CbButton.icon(
                          icon: PhosphorIconsLight.x,
                          tooltip: tr.cutRemoveSegment,
                          size: CbButtonSize.sm,
                          onPressed: _busy || _segments.length <= 1
                              ? null
                              : () => _removeSegment(i),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _toggleExportOptions() {
    setState(() => _showExportOptions = !_showExportOptions);
    if (_showExportOptions) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final optionsContext = _optionsKey.currentContext;
        if (mounted && optionsContext != null) {
          Scrollable.ensureVisible(
            optionsContext,
            duration: const Duration(milliseconds: 160),
            alignment: 1,
          );
        }
      });
    }
  }

  Widget _exportOptions(BuildContext context) {
    final tr = context.tr;
    return Padding(
      key: _optionsKey,
      padding: const EdgeInsets.only(top: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 700
              ? 3
              : constraints.maxWidth >= 450
              ? 2
              : 1;
          final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              SizedBox(
                width: width,
                child: CbSelect<bool>(
                  expand: true,
                  label: tr.cutOutputMode,
                  value: _merge,
                  enabled: !_busy,
                  items: [
                    CbSelectItem(value: false, label: tr.cutSeparate),
                    CbSelectItem(value: true, label: tr.cutMerge),
                  ],
                  onChanged: (value) => setState(() => _merge = value),
                ),
              ),
              SizedBox(
                width: width,
                child: CbSelect<String>(
                  expand: true,
                  label: tr.cutFormat,
                  value: _container,
                  enabled: !_busy,
                  items: [
                    CbSelectItem(value: 'source', label: tr.cutOriginalFormat),
                    const CbSelectItem(value: 'mkv', label: 'MKV'),
                    const CbSelectItem(value: 'mp4', label: 'MP4'),
                  ],
                  onChanged: (value) => setState(() => _container = value),
                ),
              ),
              SizedBox(
                width: width,
                child: Tooltip(
                  message: tr.cutFileDatesHint,
                  child: CbSelect<VideoCutTimestampMode>(
                    expand: true,
                    label: tr.cutFileDates,
                    value: _timestampMode,
                    enabled: !_busy,
                    items: [
                      CbSelectItem(
                        value: VideoCutTimestampMode.exportTime,
                        label: tr.cutExportTime,
                      ),
                      CbSelectItem(
                        value: VideoCutTimestampMode.sourceTime,
                        label: tr.cutSourceTime,
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _timestampMode = value),
                  ),
                ),
              ),
              CbButton(
                label: tr.cutIncludeSubtitles,
                tooltip: tr.cutSubtitleHint,
                size: CbButtonSize.sm,
                variant: CbButtonVariant.ghost,
                icon: _includeSubtitles
                    ? PhosphorIconsLight.checkSquare
                    : PhosphorIconsLight.square,
                onPressed: _busy
                    ? null
                    : () => setState(
                        () => _includeSubtitles = !_includeSubtitles,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final tr = context.tr;
    final summary = [
      _merge ? tr.cutMerge : tr.cutSeparate,
      _container == 'source' ? tr.cutOriginalFormat : _container.toUpperCase(),
      if (_timestampMode == VideoCutTimestampMode.sourceTime) tr.cutSourceTime,
      if (_includeSubtitles) tr.cutIncludeSubtitles,
    ].join(' · ');
    final options = CbButton(
      label: tr.cutOptions,
      icon: PhosphorIconsLight.slidersHorizontal,
      trailingIcon: _showExportOptions
          ? PhosphorIconsLight.caretUp
          : PhosphorIconsLight.caretDown,
      variant: CbButtonVariant.ghost,
      size: CbButtonSize.sm,
      onPressed: _toggleExportOptions,
    );
    final action = _busy
        ? CbButton(label: tr.cancel, onPressed: _service.cancel)
        : CbButton(
            label: !_merge && _segments.length > 1
                ? tr.cutExportSegments(_segments.length)
                : tr.cutExport,
            icon: PhosphorIconsLight.export,
            variant: CbButtonVariant.primary,
            onPressed: _executable == null ? null : _export,
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final meta = Text(
            _busy
                ? '${tr.cutExporting} ${(_progress * 100).round()}%'
                : summary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: CbTypography.bodySm.copyWith(
              color: context.cb.colors.textSecondary,
            ),
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy) ...[
                LinearProgressIndicator(value: _progress, minHeight: 2),
                const SizedBox(height: 8),
              ],
              if (constraints.maxWidth >= 620)
                Row(
                  children: [
                    options,
                    const SizedBox(width: 12),
                    Expanded(child: meta),
                    const SizedBox(width: 12),
                    action,
                  ],
                )
              else ...[
                Row(
                  children: [
                    options,
                    const SizedBox(width: 8),
                    Expanded(child: meta),
                  ],
                ),
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: action),
              ],
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: CbThemeBuilder.build(
        brightness: Brightness.dark,
        accent: Theme.of(context).colorScheme.primary,
      ),
      child: Builder(
        builder: (context) {
          final tr = context.tr;
          final colors = context.cb.colors;
          return Material(
            color: colors.surface,
            borderRadius: BorderRadius.circular(CbRadii.lg),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
                  child: Row(
                    children: [
                      Icon(
                        PhosphorIconsLight.scissors,
                        size: 18,
                        color: colors.icon,
                      ),
                      const SizedBox(width: 8),
                      Text(tr.cutTitle, style: CbTypography.label),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          p.basename(widget.source),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CbTypography.bodySm.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      CbButton.icon(
                        icon: PhosphorIconsLight.info,
                        tooltip: tr.cutKeyframeHint,
                        size: CbButtonSize.sm,
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (dialogContext) => CbDialog(
                            title: tr.cutTitle,
                            content: Text(tr.cutKeyframeHint),
                            actions: [
                              CbButton(
                                label: tr.close,
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(),
                              ),
                            ],
                          ),
                        ),
                      ),
                      CbButton.icon(
                        icon: PhosphorIconsLight.x,
                        tooltip: tr.close,
                        onPressed: _busy ? null : widget.onClose,
                      ),
                    ],
                  ),
                ),
                Flexible(
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              if (constraints.maxWidth >= 640) {
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _rangeEditor(
                                        context,
                                        compactTimecodes:
                                            (constraints.maxWidth - 24) / 2 <
                                            320,
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                    Expanded(child: _segmentList(context)),
                                  ],
                                );
                              }
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _rangeEditor(
                                    context,
                                    compactTimecodes:
                                        constraints.maxWidth < 320,
                                  ),
                                  _segmentList(context),
                                ],
                              );
                            },
                          ),
                          if (_showExportOptions) _exportOptions(context),
                          if (_executable == null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tr.cutFfmpegMissing,
                                    style: CbTypography.bodySm,
                                  ),
                                  CbButton(
                                    label: tr.cutChooseFfmpeg,
                                    size: CbButtonSize.sm,
                                    onPressed: _busy ? null : _chooseExecutable,
                                  ),
                                ],
                              ),
                            ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: SelectableText(
                                _error!,
                                style: CbTypography.bodySm.copyWith(
                                  color: colors.status.warning,
                                ),
                              ),
                            ),
                          if (_outputs.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          tr.cutSaved,
                                          style: CbTypography.labelSm.copyWith(
                                            color: colors.status.success,
                                          ),
                                        ),
                                      ),
                                      CbButton(
                                        label: tr.cutOpenOutput,
                                        icon: PhosphorIconsLight.folderOpen,
                                        size: CbButtonSize.sm,
                                        onPressed: _openOutput,
                                      ),
                                    ],
                                  ),
                                  for (final output in _outputs)
                                    CbButton(
                                      label: p.basename(output),
                                      icon: PhosphorIconsLight.fileVideo,
                                      tooltip: output,
                                      size: CbButtonSize.sm,
                                      variant: CbButtonVariant.ghost,
                                      onPressed: () async {
                                        try {
                                          await openVideoOutputFolderInApp(
                                            context,
                                            p.dirname(output),
                                            highlightedFileName: p.basename(
                                              output,
                                            ),
                                          );
                                        } catch (error) {
                                          if (mounted) {
                                            setState(
                                              () => _error = error.toString(),
                                            );
                                          }
                                        }
                                      },
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                _footer(context),
              ],
            ),
          );
        },
      ),
    );
  }
}

extension on Duration {
  Duration clampTo(Duration max) =>
      this < Duration.zero ? Duration.zero : (this > max ? max : this);
}
