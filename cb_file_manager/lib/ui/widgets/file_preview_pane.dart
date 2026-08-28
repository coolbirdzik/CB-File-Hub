import 'dart:io';
import 'dart:ui';

import 'package:cb_file_manager/bloc/selection/selection_state.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/components/video/video_player/video_player.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_file_manager/helpers/files/archive_path_utils.dart';
import 'package:cb_file_manager/services/archive/archive_service.dart';
import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/ui/utils/preview_syntax_highlighter.dart';
import 'package:cb_file_manager/ui/widgets/archive_preview.dart';
import 'package:cb_file_manager/services/ai/content_reader.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:path/path.dart' as path;
import 'package:pdfx/pdfx.dart';

/// Right-side file preview — airy acrylic panel, no nested chrome.
class FilePreviewPane extends StatelessWidget {
  final FolderListState state;
  final SelectionState selectionState;
  final Function(File, bool)? onOpenFile;
  final VoidCallback onClosePreview;

  const FilePreviewPane({
    Key? key,
    required this.state,
    required this.selectionState,
    required this.onOpenFile,
    required this.onClosePreview,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selectedPath = _resolveSelectedFilePath();
    final file = _resolvePreviewFile(selectedPath);
    final hasFile = file != null;
    final displayName =
        hasFile ? path.basename(file.path) : l10n.previewSelectFile;

    final panelTint = isDark
        ? theme.scaffoldBackgroundColor.withValues(alpha: 0.2)
        : theme.scaffoldBackgroundColor.withValues(alpha: 0.28);

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: ColoredBox(color: panelTint),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 48,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    stops: const [0.0, 0.35, 1.0],
                    colors: [
                      theme.shadowColor.withValues(alpha: isDark ? 0.1 : 0.04),
                      theme.shadowColor
                          .withValues(alpha: isDark ? 0.04 : 0.015),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PreviewHeader(
                title: displayName,
                showActions: hasFile,
                onOpen: hasFile && onOpenFile != null
                    ? () => onOpenFile!.call(
                          file,
                          FileTypeUtils.isVideoFile(file.path),
                        )
                    : null,
                openTooltip: l10n.open,
                onClose: onClosePreview,
                closeTooltip: l10n.hidePreview,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _buildBody(
                      context: context,
                      selectedPath: selectedPath,
                      file: file,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required String? selectedPath,
    required File? file,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mediaWash = isDark
        ? Colors.black.withValues(alpha: 0.12)
        : theme.colorScheme.onSurface.withValues(alpha: 0.04);

    if (selectedPath == null) {
      return _PreviewPlaceholder(
        icon: PhosphorIconsLight.image,
        message: l10n.previewSelectFile,
        hint: l10n.previewPaneTitle,
      );
    }

    if (selectedPath.startsWith('#network/')) {
      return _PreviewPlaceholder(
        icon: PhosphorIconsLight.wifiSlash,
        message: l10n.previewUnavailable,
      );
    }

    if (ArchivePathUtils.isArchiveEntryPath(selectedPath)) {
      return _ArchiveEntryPreview(
        key: ValueKey('preview-archive-entry-$selectedPath'),
        virtualPath: selectedPath,
      );
    }

    if (file == null) {
      return _PreviewPlaceholder(
        icon: PhosphorIconsLight.fileX,
        message: l10n.previewUnavailable,
      );
    }

    if (FileTypeUtils.isVideoFile(file.path)) {
      return ColoredBox(
        color: mediaWash,
        child: VideoPlayer.file(
          key: ValueKey('preview-video-${file.path}'),
          file: file,
          autoPlay: false,
          showControls: true,
          allowFullScreen: true,
          allowMuting: true,
        ),
      );
    }

    if (FileTypeUtils.isImageFile(file.path)) {
      return ColoredBox(
        color: mediaWash,
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 6.0,
          child: Image.file(
            file,
            key: ValueKey('preview-image-${file.path}'),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            errorBuilder: (context, error, stackTrace) => _PreviewPlaceholder(
              icon: PhosphorIconsLight.imageSquare,
              message: l10n.previewUnavailable,
            ),
          ),
        ),
      );
    }

    if (FileTypeUtils.isPdfFile(file.path)) {
      return _PdfPreview(
        key: ValueKey('preview-pdf-${file.path}'),
        file: file,
      );
    }

    if (FileTypeUtils.isTextFile(file.path)) {
      return _TextFilePreview(
        key: ValueKey('preview-text-${file.path}'),
        file: file,
      );
    }

    if (FileTypeUtils.isArchiveFile(file.path)) {
      return ArchivePreview(
        key: ValueKey('preview-archive-${file.path}'),
        archivePath: file.path,
      );
    }

    return _PreviewPlaceholder(
      icon: PhosphorIconsLight.file,
      message: l10n.previewNotSupported,
    );
  }

  String? _resolveSelectedFilePath() {
    if (selectionState.selectedFilePaths.isEmpty) return null;
    final lastSelected = selectionState.lastSelectedPath;
    if (lastSelected != null &&
        selectionState.selectedFilePaths.contains(lastSelected)) {
      return lastSelected;
    }
    return selectionState.selectedFilePaths.first;
  }

  File? _resolvePreviewFile(String? selectedPath) {
    if (selectedPath == null) return null;
    if (ArchivePathUtils.isArchiveEntryPath(selectedPath)) {
      return File(selectedPath);
    }
    final matched = state.files.whereType<File>().firstWhere(
          (file) => file.path == selectedPath,
          orElse: () => File(selectedPath),
        );
    if (!matched.existsSync()) return null;
    return matched;
  }
}

/// Opens text/PDF files in a fullscreen in-app viewer (default double-click path).
class InAppFileViewer {
  InAppFileViewer._();

  static Future<void> open(BuildContext context, File file) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => _InAppFileViewerScreen(file: file),
      ),
    );
  }
}

class _InAppFileViewerScreen extends StatelessWidget {
  final File file;

  const _InAppFileViewerScreen({required this.file});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = path.basename(file.path);

    Widget body;
    if (FileTypeUtils.isTextFile(file.path)) {
      body = _TextFilePreview(
        key: ValueKey('viewer-text-${file.path}'),
        file: file,
      );
    } else if (FileTypeUtils.isPdfFile(file.path)) {
      body = _PdfPreview(
        key: ValueKey('viewer-pdf-${file.path}'),
        file: file,
      );
    } else {
      body = Center(
        child: Text(
          AppLocalizations.of(context)!.previewNotSupported,
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: body,
    );
  }
}

class _PreviewHeader extends StatelessWidget {
  final String title;
  final bool showActions;
  final VoidCallback? onOpen;
  final String openTooltip;
  final VoidCallback onClose;
  final String closeTooltip;

  const _PreviewHeader({
    required this.title,
    required this.showActions,
    this.onOpen,
    required this.openTooltip,
    required this.onClose,
    required this.closeTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w300,
                height: 1.4,
                letterSpacing: 0.15,
                color: theme.colorScheme.onSurface.withValues(
                  alpha: showActions ? 0.58 : 0.42,
                ),
              ),
            ),
          ),
          if (showActions && onOpen != null)
            _PreviewHeaderButton(
              icon: PhosphorIconsLight.arrowSquareOut,
              tooltip: openTooltip,
              onPressed: onOpen!,
            ),
          _PreviewHeaderButton(
            icon: PhosphorIconsLight.x,
            tooltip: closeTooltip,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _PreviewHeaderButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _PreviewHeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  State<_PreviewHeaderButton> createState() => _PreviewHeaderButtonState();
}

class _PreviewHeaderButtonState extends State<_PreviewHeaderButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final idle = theme.colorScheme.onSurface.withValues(alpha: 0.26);
    final active = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    final hoverFill = theme.colorScheme.onSurface.withValues(
      alpha: isDark ? 0.05 : 0.03,
    );

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.only(left: 2),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _hovering ? hoverFill : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: _hovering ? 1 : 0.72,
              child: Icon(
                widget.icon,
                size: 14,
                color: _hovering ? active : idle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? hint;

  const _PreviewPlaceholder({
    required this.icon,
    required this.message,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = theme.colorScheme.onSurfaceVariant.withValues(
      alpha: isDark ? 0.38 : 0.34,
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 28,
              color: muted.withValues(alpha: 0.65),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: muted,
                height: 1.5,
                fontWeight: FontWeight.w300,
                letterSpacing: 0.1,
              ),
              textAlign: TextAlign.center,
            ),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Text(
                hint!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: muted.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w300,
                  letterSpacing: 0.2,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TextFilePreview extends StatefulWidget {
  final File file;

  const _TextFilePreview({Key? key, required this.file}) : super(key: key);

  @override
  State<_TextFilePreview> createState() => _TextFilePreviewState();
}

class _TextFilePreviewState extends State<_TextFilePreview> {
  static final ContentReader _reader = ContentReader();
  late Future<FileContent> _contentFuture;
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();

  @override
  void initState() {
    super.initState();
    _contentFuture = _reader.readForPreview(widget.file.path);
  }

  @override
  void didUpdateWidget(covariant _TextFilePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _contentFuture = _reader.readForPreview(widget.file.path);
    }
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textWash = isDark
        ? Colors.black.withValues(alpha: 0.14)
        : theme.colorScheme.onSurface.withValues(alpha: 0.03);

    return FutureBuilder<FileContent>(
      future: _contentFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return ColoredBox(
            color: textWash,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 1.2,
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.32),
                ),
              ),
            ),
          );
        }

        final content = snapshot.data ?? FileContent.empty;
        if (content.text.isEmpty) {
          if (content.totalLength > ContentReader.previewMaxFileSize) {
            return _PreviewPlaceholder(
              icon: PhosphorIconsLight.fileText,
              message: l10n.previewTextTooLarge,
            );
          }
          return _PreviewPlaceholder(
            icon: PhosphorIconsLight.fileText,
            message: l10n.previewUnavailable,
          );
        }

        final lines = content.text.split('\n');
        final lineNumberDigits = lines.length.toString().length;
        final useMonospace =
            FileTypeUtils.isCodeLikeTextFile(widget.file.path) ||
                _shouldSyntaxHighlight(widget.file.path);
        final textStyle = theme.textTheme.bodySmall?.copyWith(
          fontFamily: useMonospace ? 'Consolas' : null,
          fontFamilyFallback:
              useMonospace ? const ['Courier New', 'monospace'] : null,
          fontSize: useMonospace ? 12 : 13,
          height: useMonospace ? 1.55 : 1.6,
          fontWeight: FontWeight.w400,
          letterSpacing: useMonospace ? 0.1 : 0.05,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.82),
        );
        final lineNumberStyle = textStyle?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.34),
          fontFeatures: const [FontFeature.tabularFigures()],
        );
        final gutterText =
            _buildLineNumberColumn(lines.length, lineNumberDigits);
        final highlightedSpan = _shouldSyntaxHighlight(widget.file.path)
            ? PreviewSyntaxHighlighter.buildHighlightedSpan(
                source: content.text,
                filePath: widget.file.path,
                baseStyle: textStyle!,
                brightness: theme.brightness,
              )
            : TextSpan(text: content.text, style: textStyle);

        return ColoredBox(
          color: textWash,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (content.isTruncated)
                _PreviewTextBanner(message: l10n.previewTextTruncated),
              Expanded(
                child: Scrollbar(
                  controller: _verticalController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _verticalController,
                    padding: const EdgeInsets.fromLTRB(4, 10, 10, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LineNumberGutter(
                          text: gutterText,
                          style: lineNumberStyle!,
                        ),
                        Expanded(
                          child: Scrollbar(
                            controller: _horizontalController,
                            thumbVisibility: useMonospace,
                            notificationPredicate: (notification) =>
                                notification.depth == 1,
                            child: SingleChildScrollView(
                              controller: _horizontalController,
                              scrollDirection: Axis.horizontal,
                              child: SelectableText.rich(
                                highlightedSpan,
                                style: textStyle,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _shouldSyntaxHighlight(String filePath) {
    if (FileTypeUtils.isCodeLikeTextFile(filePath)) return true;
    final ext = FileTypeUtils.getFileExtension(filePath);
    return ext == '.md' || ext == '.markdown';
  }

  String _buildLineNumberColumn(int lineCount, int digits) {
    if (lineCount <= 0) return '1';
    final buffer = StringBuffer();
    for (var i = 1; i <= lineCount; i++) {
      if (i > 1) buffer.writeln();
      buffer.write('$i'.padLeft(digits));
    }
    return buffer.toString();
  }
}

class _LineNumberGutter extends StatelessWidget {
  final String text;
  final TextStyle style;

  const _LineNumberGutter({
    required this.text,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: _gutterWidth(text),
      padding: const EdgeInsets.only(left: 6, right: 10),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: theme.colorScheme.onSurface.withValues(
              alpha: isDark ? 0.08 : 0.05,
            ),
          ),
        ),
      ),
      child: Text(
        text,
        style: style,
        textAlign: TextAlign.right,
      ),
    );
  }

  double _gutterWidth(String gutterText) {
    final longestLine = gutterText.split('\n').fold<int>(
          0,
          (max, line) => line.length > max ? line.length : max,
        );
    return (longestLine * 7.2 + 22).clamp(32.0, 56.0);
  }
}

class _PreviewTextBanner extends StatelessWidget {
  final String message;

  const _PreviewTextBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(
          alpha: isDark ? 0.06 : 0.035,
        ),
      ),
      child: Text(
        message,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.62),
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

class _PdfPreview extends StatefulWidget {
  final File file;

  const _PdfPreview({Key? key, required this.file}) : super(key: key);

  @override
  State<_PdfPreview> createState() => _PdfPreviewState();
}

class _PdfPreviewState extends State<_PdfPreview> {
  late PdfController _controller;

  static Widget _buildPdfLoader(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 1.2,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.32),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _controller = PdfController(
      document: PdfDocument.openFile(widget.file.path),
    );
  }

  @override
  void didUpdateWidget(covariant _PdfPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _controller.dispose();
      _controller = PdfController(
        document: PdfDocument.openFile(widget.file.path),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PdfView(
      controller: _controller,
      builders: PdfViewBuilders<DefaultBuilderOptions>(
        options: const DefaultBuilderOptions(),
        documentLoaderBuilder: _buildPdfLoader,
        pageLoaderBuilder: _buildPdfLoader,
      ),
    );
  }
}

class _ArchiveEntryPreview extends StatefulWidget {
  final String virtualPath;

  const _ArchiveEntryPreview({
    Key? key,
    required this.virtualPath,
  }) : super(key: key);

  @override
  State<_ArchiveEntryPreview> createState() => _ArchiveEntryPreviewState();
}

class _ArchiveEntryPreviewState extends State<_ArchiveEntryPreview> {
  File? _materializedFile;
  String? _error;

  @override
  void initState() {
    super.initState();
    _materialize();
  }

  @override
  void didUpdateWidget(covariant _ArchiveEntryPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.virtualPath != widget.virtualPath) {
      _materialize();
    }
  }

  Future<void> _materialize() async {
    setState(() {
      _materializedFile = null;
      _error = null;
    });

    final location = ArchivePathUtils.parse(widget.virtualPath);
    if (location == null) return;

    try {
      final file = await locator<ArchiveService>().materializeEntryFile(
        archiveFilePath: location.archiveFile,
        entryInnerPath: location.innerPath,
        cacheKey: widget.virtualPath,
      );
      if (!mounted) return;
      setState(() => _materializedFile = file);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (_error != null) {
      return _PreviewPlaceholder(
        icon: PhosphorIconsLight.fileX,
        message: _error!,
      );
    }

    final file = _materializedFile;
    if (file == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    final entryName = ArchivePathUtils.entryFileName(widget.virtualPath) ?? '';
    if (FileTypeUtils.isImageFile(entryName)) {
      return InteractiveViewer(
        child: Image.file(file, fit: BoxFit.contain),
      );
    }

    if (FileTypeUtils.isTextFile(entryName)) {
      return _TextFilePreview(
        key: ValueKey('preview-archive-text-${widget.virtualPath}'),
        file: file,
      );
    }

    return _PreviewPlaceholder(
      icon: PhosphorIconsLight.file,
      message: l10n.previewNotSupported,
    );
  }
}
