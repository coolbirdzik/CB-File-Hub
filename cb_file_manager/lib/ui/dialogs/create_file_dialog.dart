// ignore_for_file: use_build_context_synchronously

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/ui/utils/route.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/models/file_template.dart';
import 'package:cb_file_manager/services/file_template_service.dart';
import 'package:cb_file_manager/services/directory_watcher_service.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/ui/controllers/inline_rename_controller.dart';

/// Dialog for creating a new file from a template.
/// Shows a grid (desktop) or list (mobile) of file types, filtered by detected
/// installed apps. On selection, creates the file and refreshes the folder list.
class CreateFileDialog extends StatefulWidget {
  final String directoryPath;
  final ValueChanged<String>? onAfterFileCreated;
  final InlineRenameController? inlineRenameController;
  final FolderListBloc? folderListBloc;

  const CreateFileDialog({
    super.key,
    required this.directoryPath,
    this.onAfterFileCreated,
    this.inlineRenameController,
    this.folderListBloc,
  });

  /// Opens the dialog as a modal.
  static Future<void> show(
    BuildContext context, {
    required String directoryPath,
    ValueChanged<String>? onAfterFileCreated,
    InlineRenameController? inlineRenameController,
    FolderListBloc? folderListBloc,
  }) async {
    await FileTemplateService.instance.init();
    if (!context.mounted) return;
    FolderListBloc? resolvedFolderListBloc = folderListBloc;
    if (resolvedFolderListBloc == null) {
      try {
        resolvedFolderListBloc = context.read<FolderListBloc>();
      } catch (_) {
        resolvedFolderListBloc = null;
      }
    }

    await RouteUtils.showAcrylicDialog(
      context: context,
      builder: (_) {
        final dialog = CreateFileDialog(
          directoryPath: directoryPath,
          onAfterFileCreated: onAfterFileCreated,
          inlineRenameController: inlineRenameController,
          folderListBloc: resolvedFolderListBloc,
        );

        if (resolvedFolderListBloc == null) {
          return dialog;
        }

        return BlocProvider.value(value: resolvedFolderListBloc, child: dialog);
      },
    );
  }

  @override
  State<CreateFileDialog> createState() => _CreateFileDialogState();
}

class _CreateFileDialogState extends State<CreateFileDialog> {
  String _selectedCategory = 'all';
  String _searchQuery = '';
  final _searchController = TextEditingController();

  List<FileTemplate> get _allTemplates =>
      FileTemplateService.instance.getAvailableTemplates();

  List<FileTemplate> get _filteredTemplates {
    var templates = _allTemplates;

    // Category filter
    if (_selectedCategory != 'all') {
      final cat = _categoryFromKey(_selectedCategory);
      if (cat != null) {
        templates = templates.where((t) => t.category == cat).toList();
      }
    }

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      templates = templates.where((t) {
        final name = _displayName(t).toLowerCase();
        return name.contains(q) || t.extension.toLowerCase().contains(q);
      }).toList();
    }

    return templates;
  }

  static FileTemplateCategory? _categoryFromKey(String key) {
    switch (key) {
      case 'document':
        return FileTemplateCategory.document;
      case 'spreadsheet':
        return FileTemplateCategory.spreadsheet;
      case 'presentation':
        return FileTemplateCategory.presentation;
      case 'pdf':
        return FileTemplateCategory.pdf;
      case 'image':
        return FileTemplateCategory.image;
      case 'video':
        return FileTemplateCategory.video;
      case 'audio':
        return FileTemplateCategory.audio;
      case 'archive':
        return FileTemplateCategory.archive;
      case 'code':
        return FileTemplateCategory.code;
      case 'text':
        return FileTemplateCategory.text;
      default:
        return null;
    }
  }

  String _displayName(FileTemplate t) {
    // Use known localization keys when available; fall back to hardcoded strings.
    switch (t.displayNameKey) {
      case 'fileTypeWord':
        return AppLocalizations.of(context)?.fileTypeWord ?? 'Word Document';
      case 'fileTypeExcel':
        return AppLocalizations.of(context)?.fileTypeExcel ?? 'Spreadsheet';
      case 'fileTypePowerPoint':
        return AppLocalizations.of(context)?.fileTypePowerPoint ??
            'Presentation';
      case 'fileTypeTxt':
        return AppLocalizations.of(context)?.fileTypeTxt ?? 'Text File';
      case 'fileTypePdf':
        return AppLocalizations.of(context)?.fileTypePdf ?? 'PDF Document';
      case 'fileTypeZip':
        return AppLocalizations.of(context)?.fileTypeZip ?? 'ZIP Archive';
      case 'fileTypeRar':
        return AppLocalizations.of(context)?.fileTypeRar ?? 'RAR Archive';
      case 'fileType7z':
        return AppLocalizations.of(context)?.fileType7z ?? '7Z Archive';
      case 'fileTypeCsv':
        return 'CSV Spreadsheet';
      case 'fileTypePng':
        return AppLocalizations.of(context)?.fileTypePng ?? 'PNG Image';
      case 'fileTypeJpeg':
        return AppLocalizations.of(context)?.fileTypeJpeg ?? 'JPEG Image';
      case 'fileTypeGif':
        return AppLocalizations.of(context)?.fileTypeGif ?? 'GIF Image';
      case 'fileTypeSvg':
        return AppLocalizations.of(context)?.fileTypeSvg ?? 'SVG Image';
      case 'fileTypeMp4':
        return AppLocalizations.of(context)?.fileTypeMp4 ?? 'MP4 Video';
      case 'fileTypeMp3':
        return AppLocalizations.of(context)?.fileTypeMp3 ?? 'MP3 Audio';
      case 'fileTypeWav':
        return AppLocalizations.of(context)?.fileTypeWav ?? 'WAV Audio';
      case 'fileTypeOgg':
        return AppLocalizations.of(context)?.fileTypeOgg ?? 'OGG Audio';
      default:
        // Brand-specific templates (Libre/WPS/Google) — use extension as display name
        return t.extension.toUpperCase().replaceFirst('.', '');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createFile(FileTemplate template) async {
    final defaultName = _sanitizeFileName(_displayName(template));
    final fileName = (Platform.isAndroid || Platform.isIOS)
        ? await _promptForFileName(
            defaultName: defaultName,
            extension: template.extension,
          )
        : defaultName;

    if (!mounted || fileName == null || fileName.trim().isEmpty) {
      return;
    }

    DirectoryWatcherService.instance.suppressRefreshForPath(
      widget.directoryPath,
    );

    final createdPath = await FileTemplateService.instance.createFile(
      widget.directoryPath,
      template,
      fileName,
    );

    if (!mounted) return;

    if (createdPath != null) {
      widget.folderListBloc?.add(FolderListRefresh(widget.directoryPath));
      final afterFileCreated = widget.onAfterFileCreated;
      final inlineRenameController = widget.inlineRenameController;
      Navigator.of(context).pop();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (afterFileCreated != null) {
          afterFileCreated(createdPath);
          return;
        }

        if (inlineRenameController != null &&
            !(Platform.isAndroid || Platform.isIOS)) {
          Future.delayed(const Duration(milliseconds: 100), () {
            inlineRenameController.startRename(createdPath);
          });
        }
      });
    } else {
      // Show inline error
      AppToast.error(
        context,
        AppLocalizations.of(context)?.errorCreatingFile(
              'File may already exist or path is not writable',
            ) ??
            'Error creating file',
      );
      Navigator.of(context).pop();
    }
  }

  String _sanitizeFileName(String name) {
    // Remove characters that are invalid in file names
    return name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
  }

  Future<String?> _promptForFileName({
    required String defaultName,
    required String extension,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) =>
          _CreateFileNameDialog(defaultName: defaultName, extension: extension),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final screen = MediaQuery.of(context).size;
    final isNarrow = screen.width < 500;
    final isMobile = Platform.isAndroid || Platform.isIOS;

    final dialogWidth = isNarrow
        ? (screen.width * 0.92).clamp(300.0, 420.0)
        : 520.0;
    final dialogHeight = (screen.height * 0.72).clamp(400.0, 680.0);

    return Dialog(
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(maxHeight: dialogHeight),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(isDarkMode),
            const SizedBox(height: 12),
            _buildSearchBar(isDarkMode),
            const SizedBox(height: 10),
            _buildCategoryChips(isDarkMode),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Expanded(child: _buildTemplateGrid(isDarkMode, isMobile)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDarkMode) {
    return Row(
      children: [
        Icon(
          PhosphorIconsLight.filePlus,
          color: isDarkMode ? Colors.white70 : Colors.black87,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            AppLocalizations.of(context)?.createNewFile ?? 'Create New File',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
        ),
        IconButton(
          icon: Icon(
            PhosphorIconsLight.x,
            size: 20,
            color: isDarkMode ? Colors.white54 : Colors.black54,
          ),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: AppLocalizations.of(context)?.close ?? 'Close',
        ),
      ],
    );
  }

  Widget _buildSearchBar(bool isDarkMode) {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: AppLocalizations.of(context)?.search ?? 'Search...',
        prefixIcon: Icon(
          PhosphorIconsLight.magnifyingGlass,
          size: 18,
          color: isDarkMode ? Colors.white54 : Colors.black45,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isDarkMode ? Colors.white30 : Colors.black26,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isDarkMode ? Colors.white30 : Colors.black26,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isDarkMode ? Colors.white54 : Colors.black38,
          ),
        ),
        filled: true,
        fillColor: WidgetStateColor.resolveWith((states) {
          final focused = states.contains(WidgetState.focused);
          return isDarkMode
              ? Colors.white.withAlpha(focused ? 24 : 13)
              : Colors.black.withAlpha(focused ? 12 : 5);
        }),
      ),
      onChanged: (value) {
        setState(() => _searchQuery = value);
      },
    );
  }

  Widget _buildCategoryChips(bool isDarkMode) {
    final l10n = AppLocalizations.of(context);
    final categories = [
      {'key': 'all', 'label': l10n?.all ?? 'All'},
      {'key': 'document', 'label': l10n?.document ?? 'Document'},
      {'key': 'spreadsheet', 'label': l10n?.fileTypeExcel ?? 'Spreadsheet'},
      {
        'key': 'presentation',
        'label': l10n?.fileTypePowerPoint ?? 'Presentation',
      },
      {'key': 'pdf', 'label': 'PDF'},
      {'key': 'code', 'label': 'Code'},
      {'key': 'text', 'label': 'Text'},
      {'key': 'image', 'label': l10n?.image ?? 'Image'},
      {'key': 'audio', 'label': l10n?.audio ?? 'Audio'},
      {'key': 'video', 'label': l10n?.video ?? 'Video'},
      {'key': 'archive', 'label': l10n?.fileTypeZip ?? 'Archive'},
    ];

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final key = categories[index]['key']!;
          final label = categories[index]['label']!;
          final isSelected = _selectedCategory == key;
          return FilterChip(
            label: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isSelected
                    ? (isDarkMode ? Colors.white : Colors.white)
                    : (isDarkMode ? Colors.white70 : Colors.black87),
              ),
            ),
            selected: isSelected,
            onSelected: (_) {
              setState(() => _selectedCategory = key);
            },
            backgroundColor: isDarkMode
                ? Colors.white.withAlpha(13)
                : Colors.black.withAlpha(8),
            selectedColor: isDarkMode ? Colors.blueGrey[700] : Colors.blue,
            checkmarkColor: Colors.white,
            side: BorderSide(
              color: isSelected
                  ? (isDarkMode ? Colors.transparent : Colors.blue)
                  : (isDarkMode ? Colors.white24 : Colors.black26),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }

  Widget _buildTemplateGrid(bool isDarkMode, bool isMobile) {
    final templates = _filteredTemplates;

    if (templates.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsLight.file,
              size: 48,
              color: isDarkMode ? Colors.white30 : Colors.black26,
            ),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty
                  ? (AppLocalizations.of(context)?.searchVideos ??
                        'No results for "$_searchQuery"')
                  : 'No templates available',
              style: TextStyle(
                color: isDarkMode ? Colors.white54 : Colors.black54,
              ),
            ),
          ],
        ),
      );
    }

    if (isMobile) {
      return ListView.separated(
        itemCount: templates.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          return _TemplateTile(
            template: templates[index],
            displayName: _displayName(templates[index]),
            onTap: () => _createFile(templates[index]),
          );
        },
      );
    }

    // Desktop: wrap grid
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 480 ? 4 : 3;
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.0,
          ),
          itemCount: templates.length,
          itemBuilder: (context, index) {
            return _TemplateCard(
              template: templates[index],
              displayName: _displayName(templates[index]),
              onTap: () => _createFile(templates[index]),
            );
          },
        );
      },
    );
  }
}

class _CreateFileNameDialog extends StatefulWidget {
  final String defaultName;
  final String extension;

  const _CreateFileNameDialog({
    required this.defaultName,
    required this.extension,
  });

  @override
  State<_CreateFileNameDialog> createState() => _CreateFileNameDialogState();
}

class _CreateFileNameDialogState extends State<_CreateFileNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.defaultName);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.createNewFile),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              labelText: l10n.fileName,
              border: const OutlineInputBorder(),
            ),
            autofocus: true,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          Text(
            'Extension: ${widget.extension}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(onPressed: _submit, child: Text(l10n.create)),
      ],
    );
  }
}

/// A grid card for a single file template (desktop).
class _TemplateCard extends StatelessWidget {
  final FileTemplate template;
  final String displayName;
  final VoidCallback onTap;

  const _TemplateCard({
    required this.template,
    required this.displayName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Tooltip(
      message: 'Creates a${template.extension} file',
      child: Material(
        color: isDarkMode
            ? Colors.white.withAlpha(13)
            : Colors.black.withAlpha(5),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  template.icon,
                  size: 32,
                  color: _iconColor(template.category, isDarkMode),
                ),
                const SizedBox(height: 6),
                Text(
                  displayName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
                if (template.hasBrandBadge) ...[
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: _brandColor(template.brand, isDarkMode),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      template.brandLabel,
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _iconColor(FileTemplateCategory category, bool isDarkMode) {
    final base = isDarkMode ? Colors.white : Colors.black87;
    switch (category) {
      case FileTemplateCategory.document:
        return Colors.blue[300] ?? base;
      case FileTemplateCategory.spreadsheet:
        return Colors.green[300] ?? base;
      case FileTemplateCategory.presentation:
        return Colors.orange[300] ?? base;
      case FileTemplateCategory.pdf:
        return Colors.red[300] ?? base;
      case FileTemplateCategory.code:
        return Colors.purple[300] ?? base;
      case FileTemplateCategory.image:
        return Colors.pink[300] ?? base;
      case FileTemplateCategory.audio:
        return Colors.teal[300] ?? base;
      case FileTemplateCategory.video:
        return Colors.indigo[300] ?? base;
      case FileTemplateCategory.archive:
        return Colors.brown[300] ?? base;
      case FileTemplateCategory.text:
        return Colors.grey[300] ?? base;
      case FileTemplateCategory.other:
        return base;
    }
  }

  Color _brandColor(FileTemplateBrand brand, bool isDarkMode) {
    switch (brand) {
      case FileTemplateBrand.microsoft:
        return Colors.blue[700]!;
      case FileTemplateBrand.libre:
        return Colors.green[700]!;
      case FileTemplateBrand.wps:
        return Colors.amber[700]!;
      case FileTemplateBrand.google:
        return Colors.red[700]!;
      case FileTemplateBrand.generic:
        return Colors.grey;
    }
  }
}

/// A list tile for a single file template (mobile).
class _TemplateTile extends StatelessWidget {
  final FileTemplate template;
  final String displayName;
  final VoidCallback onTap;

  const _TemplateTile({
    required this.template,
    required this.displayName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return ListTile(
      leading: Icon(
        template.icon,
        size: 28,
        color: _iconColor(template.category, isDarkMode),
      ),
      title: Text(
        displayName,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: isDarkMode ? Colors.white : Colors.black87,
        ),
      ),
      subtitle: Text(
        template.extension,
        style: TextStyle(
          fontSize: 12,
          color: isDarkMode ? Colors.white54 : Colors.black54,
        ),
      ),
      trailing: template.hasBrandBadge
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _brandColor(template.brand, isDarkMode),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                template.brandLabel,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : null,
      onTap: onTap,
    );
  }

  Color _iconColor(FileTemplateCategory category, bool isDarkMode) {
    final base = isDarkMode ? Colors.white : Colors.black87;
    switch (category) {
      case FileTemplateCategory.document:
        return Colors.blue[300] ?? base;
      case FileTemplateCategory.spreadsheet:
        return Colors.green[300] ?? base;
      case FileTemplateCategory.presentation:
        return Colors.orange[300] ?? base;
      case FileTemplateCategory.pdf:
        return Colors.red[300] ?? base;
      case FileTemplateCategory.code:
        return Colors.purple[300] ?? base;
      case FileTemplateCategory.image:
        return Colors.pink[300] ?? base;
      case FileTemplateCategory.audio:
        return Colors.teal[300] ?? base;
      case FileTemplateCategory.video:
        return Colors.indigo[300] ?? base;
      case FileTemplateCategory.archive:
        return Colors.brown[300] ?? base;
      case FileTemplateCategory.text:
        return Colors.grey[300] ?? base;
      case FileTemplateCategory.other:
        return base;
    }
  }

  Color _brandColor(FileTemplateBrand brand, bool isDarkMode) {
    switch (brand) {
      case FileTemplateBrand.microsoft:
        return Colors.blue[700]!;
      case FileTemplateBrand.libre:
        return Colors.green[700]!;
      case FileTemplateBrand.wps:
        return Colors.amber[700]!;
      case FileTemplateBrand.google:
        return Colors.red[700]!;
      case FileTemplateBrand.generic:
        return Colors.grey;
    }
  }
}
