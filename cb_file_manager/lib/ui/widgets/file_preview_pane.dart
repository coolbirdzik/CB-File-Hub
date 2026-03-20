import 'dart:io';

import 'package:cb_file_manager/bloc/selection/selection_state.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/components/video/video_player/video_player.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:path/path.dart' as path;
import 'package:pdfx/pdfx.dart';

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
    final selectedPath = _resolveSelectedFilePath();
    final file = _resolvePreviewFile(selectedPath);
    final displayName =
        file != null ? path.basename(file.path) : l10n.previewPaneTitle;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: Row(
            children: [
              const Icon(PhosphorIconsLight.eye, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (file != null && onOpenFile != null)
                IconButton(
                  icon: const Icon(PhosphorIconsLight.arrowSquareOut, size: 18),
                  tooltip: l10n.open,
                  onPressed: () {
                    onOpenFile?.call(
                      file,
                      FileTypeUtils.isVideoFile(file.path),
                    );
                  },
                ),
              IconButton(
                icon: const Icon(PhosphorIconsLight.x, size: 18),
                tooltip: l10n.hidePreview,
                onPressed: onClosePreview,
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildBody(
            context: context,
            selectedPath: selectedPath,
            file: file,
          ),
        ),
      ],
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required String? selectedPath,
    required File? file,
  }) {
    final l10n = AppLocalizations.of(context)!;

    if (selectedPath == null) {
      return _PreviewPlaceholder(
        icon: PhosphorIconsLight.eye,
        message: l10n.previewSelectFile,
      );
    }

    if (selectedPath.startsWith('#network/')) {
      return _PreviewPlaceholder(
        icon: PhosphorIconsLight.wifiSlash,
        message: l10n.previewUnavailable,
      );
    }

    if (file == null) {
      return _PreviewPlaceholder(
        icon: PhosphorIconsLight.warningCircle,
        message: l10n.previewUnavailable,
      );
    }

    if (FileTypeUtils.isVideoFile(file.path)) {
      return Container(
        color: Colors.black,
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
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
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

    if (_isPdfFile(file.path)) {
      return _PdfPreview(
        key: ValueKey('preview-pdf-${file.path}'),
        file: file,
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
    final matched = state.files.whereType<File>().firstWhere(
          (file) => file.path == selectedPath,
          orElse: () => File(selectedPath),
        );
    if (!matched.existsSync()) return null;
    return matched;
  }

  bool _isPdfFile(String filePath) {
    return filePath.toLowerCase().endsWith('.pdf');
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  final IconData icon;
  final String message;

  const _PreviewPlaceholder({
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: color),
          const SizedBox(height: 12),
          Text(
            message,
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
            textAlign: TextAlign.center,
          ),
        ],
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
    return const Center(child: CircularProgressIndicator());
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
      builders: const PdfViewBuilders<DefaultBuilderOptions>(
        options: DefaultBuilderOptions(),
        documentLoaderBuilder: _buildPdfLoader,
        pageLoaderBuilder: _buildPdfLoader,
      ),
    );
  }
}
