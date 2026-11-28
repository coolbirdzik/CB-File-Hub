import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/ui/controllers/selection_tags_controller.dart';
import 'package:cb_file_manager/ui/dialogs/open_with_dialog.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_file_manager/ui/utils/format_utils.dart';
import 'package:cb_file_manager/ui/widgets/file_properties_tabs.dart';
import 'package:cb_file_manager/ui/widgets/selection_tag_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as pathlib;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../utils/route.dart';

class FileDetailsScreen extends StatefulWidget {
  final File file;

  /// 0 opens the overview; 1 is the existing Manage Tags navigation target.
  final int initialTab;

  const FileDetailsScreen({super.key, required this.file, this.initialTab = 0});

  /// Keep the current folder or search view behind the Properties inspector.
  static Future<void> show(
    BuildContext context, {
    required File file,
    int initialTab = 0,
  }) => RouteUtils.showAcrylicDialog<void>(
    context: context,
    builder: (_) => FileDetailsScreen(file: file, initialTab: initialTab),
  );

  @override
  State<FileDetailsScreen> createState() => _FileDetailsScreenState();
}

class _FileDetailsScreenState extends State<FileDetailsScreen> {
  late Future<FileStat> _fileStatFuture;
  final _inspectorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _fileStatFuture = widget.file.stat();
  }

  @override
  void didUpdateWidget(covariant FileDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _fileStatFuture = widget.file.stat();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final media = MediaQuery.of(context);
    final contentHeight = (media.size.height - media.viewInsets.vertical - 144)
        .clamp(160.0, 420.0);
    return CbDialog(
      title: l.properties,
      width: 680,
      content: SizedBox(
        width: double.infinity,
        height: contentHeight,
        child: FutureBuilder<FileStat>(
          future: _fileStatFuture,
          builder: (context, snapshot) {
            final stat = snapshot.data;
            final isDirectory = stat?.type == FileSystemEntityType.directory;
            return LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 280;
                final inspector = FilePropertiesTabs(
                  key: _inspectorKey,
                  filePath: widget.file.path,
                  statFuture: _fileStatFuture,
                  isDirectory: isDirectory,
                  scrollContent: !compact,
                  initialTab: widget.initialTab == 1
                      ? FilePropertiesTab.tags
                      : FilePropertiesTab.overview,
                  tags: isDirectory
                      ? null
                      : _PropertiesTags(
                          key: ValueKey(widget.file.path),
                          filePath: widget.file.path,
                        ),
                );
                final header = _header(context, l, stat, isDirectory);
                if (compact) {
                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        header,
                        const SizedBox(height: CbSpacing.lg),
                        inspector,
                      ],
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    const SizedBox(height: CbSpacing.lg),
                    Expanded(child: inspector),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  IconData _fileIcon(bool isDirectory) {
    final filePath = widget.file.path;
    if (isDirectory) return PhosphorIconsLight.folder;
    if (FileTypeUtils.isImageFile(filePath)) return PhosphorIconsLight.image;
    if (FileTypeUtils.isVideoFile(filePath)) {
      return PhosphorIconsLight.videoCamera;
    }
    if (FileTypeUtils.isAudioFile(filePath)) {
      return PhosphorIconsLight.musicNotes;
    }
    if (FileTypeUtils.isDocumentFile(filePath)) {
      return PhosphorIconsLight.fileText;
    }
    if (FileTypeUtils.isSpreadsheetFile(filePath)) {
      return PhosphorIconsLight.squaresFour;
    }
    return PhosphorIconsLight.file;
  }

  Widget _header(
    BuildContext context,
    AppLocalizations l,
    FileStat? stat,
    bool isDirectory,
  ) {
    final c = context.cbColors;
    final filePath = widget.file.path;
    final type = isDirectory
        ? l.folder
        : FileTypeUtils.getFileTypeLabel(
            context,
            FileTypeUtils.getFileExtension(filePath),
          );
    final size =
        stat != null && !isDirectory && stat.type == FileSystemEntityType.file
        ? FormatUtils.formatFileSizeExact(stat.size)
        : null;
    return CbSurface(
      radius: CbRadii.md,
      padding: const EdgeInsets.all(CbSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CbSurface(
                radius: CbRadii.md,
                color: c.fill,
                width: CbSpacing.xxxl,
                height: CbSpacing.xxxl,
                child: Center(
                  child: Icon(
                    _fileIcon(isDirectory),
                    size: CbSizes.iconXl,
                    color: c.icon,
                  ),
                ),
              ),
              const SizedBox(width: CbSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pathlib.basename(filePath),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: CbTypography.headingLg.copyWith(
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: CbSpacing.xxs),
                    Text(
                      [type, ?size].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: CbTypography.bodySm.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!isDirectory) ...[
            const SizedBox(height: CbSpacing.md),
            Wrap(
              spacing: CbSpacing.sm,
              runSpacing: CbSpacing.xs,
              children: [
                CbButton(
                  label: l.openWith,
                  icon: PhosphorIconsLight.arrowSquareOut,
                  size: CbButtonSize.sm,
                  onPressed: _showOpenWithDialog,
                ),
                CbButton(
                  label: l.chooseDefaultApp,
                  icon: PhosphorIconsLight.squaresFour,
                  size: CbButtonSize.sm,
                  variant: CbButtonVariant.ghost,
                  onPressed: () =>
                      _showOpenWithDialog(saveAsDefaultOnSelect: true),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showOpenWithDialog({bool saveAsDefaultOnSelect = false}) {
    RouteUtils.showAcrylicDialog(
      context: context,
      builder: (context) => OpenWithDialog(
        filePath: widget.file.path,
        saveAsDefaultOnSelect: saveAsDefaultOnSelect,
      ),
    );
  }
}

/// The same immediate-save tag editor used by the docked Properties pane.
class _PropertiesTags extends StatefulWidget {
  const _PropertiesTags({super.key, required this.filePath});
  final String filePath;

  @override
  State<_PropertiesTags> createState() => _PropertiesTagsState();
}

class _PropertiesTagsState extends State<_PropertiesTags> {
  final _controller = SelectionTagsController();

  @override
  void initState() {
    super.initState();
    unawaited(_controller.select([widget.filePath]));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final failure in _controller.failures)
            Padding(
              padding: const EdgeInsets.only(bottom: CbSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${l.propertiesTagFailure}: ${failure.paths.length}',
                      style: CbTypography.bodySm.copyWith(
                        color: context.cbColors.status.danger,
                      ),
                    ),
                  ),
                  CbButton(
                    label: l.retry,
                    size: CbButtonSize.xs,
                    onPressed: _controller.saving
                        ? null
                        : () => _controller.retry(failure),
                  ),
                ],
              ),
            ),
          SelectionTagEditor(controller: _controller),
        ],
      ),
    );
  }
}
