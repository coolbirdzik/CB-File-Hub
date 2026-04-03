import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/widgets/chips_input.dart';
import 'package:cb_file_manager/helpers/tags/batch_tag_manager.dart';
import 'package:cb_file_manager/helpers/core/uri_utils.dart';
import 'dart:ui' as ui; // Import for ImageFilter
import 'package:cb_file_manager/ui/widgets/tag_management_section.dart';
import 'package:cb_file_manager/ui/widgets/tag_chip.dart';
import 'package:cb_file_manager/utils/app_logger.dart';
import '../../utils/route.dart';
import '../core/tab_manager.dart';
import '../core/tab_data.dart';

/// Opens a new tab with search results for the selected tag
void _openTagSearchTab(BuildContext context, String tag) {
  final searchSystemId = UriUtils.buildTagSearchPath(tag);
  final tabName = 'Tag: $tag';

  final tabBloc = BlocProvider.of<TabManagerBloc>(context);

  final existingTab = tabBloc.state.tabs.firstWhere(
    (tab) => tab.path == searchSystemId,
    orElse: () => TabData(id: '', name: '', path: ''),
  );

  if (existingTab.id.isNotEmpty) {
    tabBloc.add(SwitchToTab(existingTab.id));
  } else {
    tabBloc.add(
      AddTab(
        path: searchSystemId,
        name: tabName,
        switchToTab: true,
      ),
    );
  }
}

/// Dialog for adding a tag to a file
void showAddTagToFileDialog(BuildContext context, String filePath) {
  final Size screenSize = MediaQuery.of(context).size;
  final double dialogWidth = screenSize.width * 0.5;
  final double dialogHeight = screenSize.height * 0.6;
  AppLogger.info('[ManageTags][Dialog] Opening dialog for $filePath');
  debugPrint('[ManageTags][Dialog] Opening dialog for filePath=$filePath');

  void refreshParentUI(String filePath, {bool preserveScroll = true}) {
    debugPrint(
        '[ManageTags][Dialog] Refreshing parent UI for filePath=$filePath preserveScroll=$preserveScroll');
    TagManager.clearCache();
    if (preserveScroll) {
      TagManager.instance.notifyTagChanged("preserve_scroll:$filePath");
    } else {
      TagManager.instance.notifyTagChanged(filePath);
    }
    TagManager.instance.notifyTagChanged(filePath);
    TagManager.instance.notifyTagChanged("global:tag_updated");
  }

  showDialog(
    context: context,
    builder: (dialogContext) {
      AppLogger.debug('[ManageTags][Dialog] showDialog builder for $filePath');
      return _SingleFileTagDialog(
        filePath: filePath,
        dialogWidth: dialogWidth,
        dialogHeight: dialogHeight,
      );
    },
  ).then((result) {
    if (result == true) {
      AppLogger.info('[ManageTags][Dialog] Refresh triggered after save',
          error: 'filePath=$filePath');
      refreshParentUI(filePath);
      if (context.mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(l10n.tagsSavedSuccessfully)),
        );
      }
    }
  });
}

class _SingleFileTagDialog extends StatefulWidget {
  final String filePath;
  final double dialogWidth;
  final double dialogHeight;

  const _SingleFileTagDialog({
    required this.filePath,
    required this.dialogWidth,
    required this.dialogHeight,
  });

  @override
  State<_SingleFileTagDialog> createState() => _SingleFileTagDialogState();
}

class _SingleFileTagDialogState extends State<_SingleFileTagDialog> {
  List<String> _originalTags = <String>[];
  List<String> _selectedTags = <String>[];
  List<String> _tagSuggestions = <String>[];
  String _draftTagText = '';
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadTags() async {
    AppLogger.info('[ManageTags][Dialog] Loading tags',
        error: 'filePath=${widget.filePath}');
    try {
      final tags = await TagManager.getTags(widget.filePath);
      if (!mounted) {
        return;
      }

      setState(() {
        _originalTags = List<String>.from(tags);
        _selectedTags = List<String>.from(tags);
        _isLoading = false;
      });
      AppLogger.info('[ManageTags][Dialog] Loaded tags',
          error: 'filePath=${widget.filePath} tags=$tags');
    } catch (error, stackTrace) {
      AppLogger.error(
        '[ManageTags][Dialog] Failed to load tags',
        error: 'filePath=${widget.filePath} error=$error',
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateTagSuggestions(String text) async {
    final query = text.trim();
    if (query.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _tagSuggestions = <String>[];
      });
      return;
    }

    final suggestions = await TagManager.instance.searchTags(query);
    if (!mounted) {
      return;
    }

    setState(() {
      _tagSuggestions = suggestions
          .where((tag) => !_containsTag(tag))
          .take(6)
          .toList(growable: false);
    });
  }

  bool _containsTag(String tag) {
    final normalizedTag = tag.trim().toLowerCase();
    return _selectedTags.any((selectedTag) {
      return selectedTag.trim().toLowerCase() == normalizedTag;
    });
  }

  void _addTag(String rawTag) {
    final tag = rawTag.trim();
    if (tag.isEmpty || _containsTag(tag)) {
      _draftTagText = '';
      return;
    }

    setState(() {
      _selectedTags = <String>[..._selectedTags, tag];
      _draftTagText = '';
      _tagSuggestions = <String>[];
    });
    AppLogger.info('[ManageTags][Dialog] Tag added',
        error: 'filePath=${widget.filePath} tag=$tag');
  }

  void _removeTag(String tag) {
    setState(() {
      _selectedTags = _selectedTags.where((value) => value != tag).toList();
    });
    AppLogger.info('[ManageTags][Dialog] Tag removed',
        error: 'filePath=${widget.filePath} tag=$tag');
  }

  void _commitDraftTag() {
    final draft = _draftTagText.trim();
    if (draft.isEmpty) {
      return;
    }
    _addTag(draft);
  }

  bool get _hasChanges {
    final original = _originalTags.map((tag) => tag.trim()).toSet();
    final current = _selectedTags.map((tag) => tag.trim()).toSet();
    return original.length != current.length || !original.containsAll(current);
  }

  Future<void> _save() async {
    if (_isSaving) {
      return;
    }

    AppLogger.info('[ManageTags][Dialog] Save pressed',
        error:
            'filePath=${widget.filePath} selectedTags=$_selectedTags draftTagText=$_draftTagText');

    setState(() {
      _isSaving = true;
    });

    try {
      _commitDraftTag();

      final tagsToPersist = List<String>.from(_selectedTags);
      AppLogger.info('[ManageTags][Dialog] Persisting tags',
          error: 'filePath=${widget.filePath} tags=$tagsToPersist');

      if (_hasChanges || _draftTagText.trim().isNotEmpty) {
        final success = await TagManager.setTags(widget.filePath, tagsToPersist);
        if (!success) {
          throw Exception('Failed to persist tags for "${widget.filePath}"');
        }
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context, rootNavigator: true).pop(true);
    } catch (error, stackTrace) {
      final l10n = AppLocalizations.of(context)!;
      AppLogger.error(
        '[ManageTags][Dialog] Save failed',
        error: 'filePath=${widget.filePath} error=$error',
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.errorSavingTags(error.toString())),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Widget _buildSuggestions() {
    if (_tagSuggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildSectionCard(
      icon: PhosphorIconsLight.magnifyingGlass,
      title: AppLocalizations.of(context)!.tagSuggestions,
      subtitle: 'Click to add',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: _tagSuggestions.map((suggestion) {
          return TagChip(
            tag: suggestion,
            onTap: () => _addTag(suggestion),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTagInputSection(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return _buildSectionCard(
      icon: PhosphorIconsLight.pencilSimpleLine,
      title: l10n.addTag,
      subtitle: 'Type a new tag or pick from the library below',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChipsInput<String>(
            values: _selectedTags,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Colors.transparent,
                  width: 0,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Colors.transparent,
                  width: 0,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: theme.colorScheme.primary.withValues(alpha: 0.45),
                  width: 1,
                ),
              ),
              labelText: l10n.tagName,
              hintText: l10n.enterTagName,
              prefixIcon: const Icon(PhosphorIconsLight.tag),
              filled: true,
              fillColor: isDarkMode
                  ? theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.42)
                  : theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.2),
            ),
            style: const TextStyle(fontSize: 16),
            onChanged: (updatedTags) {
              setState(() {
                _selectedTags = List<String>.from(updatedTags);
              });
            },
            onTextChanged: (value) {
              _draftTagText = value;
              _updateTagSuggestions(value);
            },
            onSubmitted: _addTag,
            chipBuilder: (context, tag) {
              return TagInputChip(
                tag: tag,
                onDeleted: _removeTag,
                onSelected: (_) {},
              );
            },
          ),
          if (_tagSuggestions.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildSuggestions(),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.manageTags,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    PhosphorIconsLight.file,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.filePath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.fromLTRB(28, 20, 28, 16),
        content: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(
            maxWidth: widget.dialogWidth,
            maxHeight: widget.dialogHeight,
            minHeight: widget.dialogHeight * 0.72,
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTagInputSection(l10n),
                      const SizedBox(height: 18),
                      _buildSectionCard(
                        icon: PhosphorIconsLight.sparkle,
                        title: 'Quick Picks',
                        subtitle: 'Choose from popular or recently used tags',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            PopularTagsWidget(
                              onTagSelected: _addTag,
                            ),
                            const SizedBox(height: 20),
                            RecentTagsWidget(
                              onTagSelected: _addTag,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextFieldTapRegion(
            child: TextButton(
              onPressed: _isSaving
                  ? null
                  : () {
                      AppLogger.info('[ManageTags][Dialog] Close pressed',
                          error: 'filePath=${widget.filePath}');
                      Navigator.of(context, rootNavigator: true).pop(false);
                    },
              style: TextButton.styleFrom(
                textStyle: const TextStyle(fontSize: 16),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              child: Text(l10n.close.toUpperCase()),
            ),
          ),
          TextFieldTapRegion(
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                textStyle: const TextStyle(fontSize: 16),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.save.toUpperCase()),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog for deleting a tag from a file
void showDeleteTagDialog(
  BuildContext context,
  String filePath,
  List<String> tags,
) {
  String? selectedTag = tags.isNotEmpty ? tags.first : null;

  showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: AlertDialog(
              title: Text(AppLocalizations.of(context)!.removeTag),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              content: Container(
                width: double.maxFinite,
                constraints: const BoxConstraints(
                  maxWidth: 450,
                  minWidth: 350,
                  minHeight: 100,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppLocalizations.of(context)!.selectTagToRemove),
                    const SizedBox(height: 16),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: selectedTag,
                      items: tags.map((tag) {
                        return DropdownMenuItem<String>(
                          value: tag,
                          child: Text(tag),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedTag = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    RouteUtils.safePopDialog(context);
                  },
                  child:
                      Text(AppLocalizations.of(context)!.cancel.toUpperCase()),
                ),
                TextButton(
                  onPressed: () async {
                    if (selectedTag != null) {
                      // Pre-extract all context-dependent values before async gap
                      final l10n = AppLocalizations.of(context)!;
                      final bloc = BlocProvider.of<FolderListBloc>(context,
                          listen: false);
                      final scaffoldMessenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(context);

                      try {
                        await TagManager.removeTag(filePath, selectedTag!);
                        TagManager.clearCache();

                        try {
                          bloc.add(RemoveTagFromFile(filePath, selectedTag!));
                        } catch (_) {}

                        TagManager.instance
                            .notifyTagChanged("tag_only:$filePath");

                        try {
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text(l10n.tagDeleted(selectedTag!)),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                          navigator.pop();
                        } catch (_) {}
                      } catch (e) {
                        try {
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content:
                                  Text(l10n.errorDeletingTag(e.toString())),
                              backgroundColor: Colors.red,
                            ),
                          );
                        } catch (_) {}
                      }
                    } else {
                      try {
                        Navigator.of(context).pop();
                      } catch (_) {}
                    }
                  },
                  child: Text(
                      AppLocalizations.of(context)!.removeTag.toUpperCase()),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

/// Dialog for batch adding tags
void showBatchAddTagDialog(BuildContext context, List<String> selectedFiles) {
  final focusNode = FocusNode();
  final TextEditingController textController = TextEditingController();
  List<String> tagSuggestions = [];
  List<String> selectedTags = [];
  String draftTagText = '';

  final Size screenSize = MediaQuery.of(context).size;
  final double dialogWidth = screenSize.width * 0.5;
  final double dialogHeight = screenSize.height * 0.6;
  AppLogger.info('[ManageTags][BatchDialog] Opening batch dialog',
      error: 'selectedFiles=$selectedFiles');

  void updateTagSuggestions(String text) async {
    if (text.isEmpty) {
      tagSuggestions = [];
      return;
    }

    final suggestions = await TagManager.instance.searchTags(text);
    tagSuggestions =
        suggestions.where((tag) => !selectedTags.contains(tag)).toList();
  }

  void addTag(String tag) {
    if (tag.trim().isEmpty) return;

    if (!selectedTags.contains(tag.trim())) {
      selectedTags.add(tag.trim());
      textController.clear();
      draftTagText = '';
    }
  }

  void commitDraftTag() {
    final trimmedTag = draftTagText.trim();
    if (trimmedTag.isEmpty) {
      return;
    }

    addTag(trimmedTag);
    tagSuggestions = [];
  }

  void refreshParentUIBatch() {
    TagManager.clearCache();

    try {
      if (selectedFiles.isNotEmpty) {
        for (final file in selectedFiles) {
          TagManager.instance.notifyTagChanged("preserve_scroll:$file");
        }
      }
    } catch (_) {}
  }

  final batchTagManager = BatchTagManager.getInstance();
  batchTagManager.findCommonTags(selectedFiles).then((commonTags) {
    if (!context.mounted) return;

    selectedTags = commonTags;
    AppLogger.info('[ManageTags][BatchDialog] Loaded common tags',
        error: 'selectedFiles=$selectedFiles commonTags=$commonTags');

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            void handleTextChange(String value) {
              draftTagText = value;
              updateTagSuggestions(value);
              setState(() {});
            }

            void handleTagSubmit(String value) {
              if (value.trim().isNotEmpty) {
                setState(() {
                  addTag(value);
                  tagSuggestions = [];
                });
                AppLogger.info('[ManageTags][BatchDialog] Tag submitted',
                    error: 'selectedFiles=$selectedFiles tag=$value');
              }
            }

            void handleTagSelected(String tag) {
              RouteUtils.safePopDialog(context);
              _openTagSearchTab(context, tag);
            }

            return BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: AlertDialog(
                title: Text(
                  AppLocalizations.of(context)!
                      .batchAddTags(selectedFiles.length),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                content: Container(
                  width: double.maxFinite,
                  constraints: BoxConstraints(
                    maxWidth: dialogWidth,
                    maxHeight: dialogHeight,
                    minHeight: dialogHeight * 0.7,
                  ),
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Focus(
                          focusNode: focusNode,
                          child: ChipsInput<String>(
                            values: selectedTags,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16.0),
                              ),
                              labelText: AppLocalizations.of(context)!.tagName,
                              hintText:
                                  AppLocalizations.of(context)!.enterTagName,
                              prefixIcon: const Icon(PhosphorIconsLight.tag),
                              filled: true,
                              fillColor: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.grey[800]
                                  : Colors.grey[100],
                            ),
                            onChanged: (updatedTags) {
                              setState(() {
                                selectedTags.clear();
                                selectedTags.addAll(updatedTags);
                              });
                            },
                            onTextChanged: handleTextChange,
                            onSubmitted: handleTagSubmit,
                            chipBuilder: (context, tag) {
                              return TagInputChip(
                                tag: tag,
                                onDeleted: (removedTag) {
                                  setState(() {
                                    selectedTags.remove(removedTag);
                                  });
                                },
                                onSelected: (selectedTag) {},
                              );
                            },
                          ),
                        ),
                        if (tagSuggestions.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.grey[800]
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(16.0),
                              border: Border.all(
                                color: Colors.grey.withValues(alpha: 0.2),
                              ),
                            ),
                            child: ListView.builder(
                              shrinkWrap: true,
                              physics: const ClampingScrollPhysics(),
                              itemCount: tagSuggestions.length > 5
                                  ? 5
                                  : tagSuggestions.length,
                              itemBuilder: (context, index) {
                                final suggestion = tagSuggestions[index];
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(PhosphorIconsLight.tag,
                                      size: 18),
                                  title: Text(suggestion),
                                  onTap: () {
                                    setState(() {
                                      addTag(suggestion);
                                      tagSuggestions = [];
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 24),
                        if (selectedTags.isNotEmpty)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocalizations.of(context)!.selectedTags,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8.0,
                                runSpacing: 8.0,
                                children: selectedTags.map((tag) {
                                  return Chip(
                                    label: Text(tag),
                                    onDeleted: () {
                                      setState(() {
                                        selectedTags.remove(tag);
                                      });
                                    },
                                    deleteIcon: const Icon(PhosphorIconsLight.x,
                                        size: 16),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        const SizedBox(height: 24),
                        PopularTagsWidget(onTagSelected: handleTagSelected),
                        const SizedBox(height: 24),
                        RecentTagsWidget(onTagSelected: handleTagSelected),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextFieldTapRegion(
                    child: TextButton(
                      onPressed: () {
                        RouteUtils.safePopDialog(context);
                      },
                      style: TextButton.styleFrom(
                        textStyle: const TextStyle(fontSize: 16),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                      child: Text(
                          AppLocalizations.of(context)!.cancel.toUpperCase()),
                    ),
                  ),
                  TextFieldTapRegion(
                    child: ElevatedButton(
                      onPressed: () async {
                        AppLogger.info('[ManageTags][BatchDialog] Save pressed',
                            error:
                                'selectedFiles=$selectedFiles selectedTags=$selectedTags draftTagText=$draftTagText');
                        final l10n = AppLocalizations.of(context)!;
                        final bloc = BlocProvider.of<FolderListBloc>(context,
                            listen: false);
                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        final navigator = Navigator.of(context);

                        try {
                          setState(() {
                            commitDraftTag();
                          });
                          try {
                            scaffoldMessenger.showSnackBar(
                              SnackBar(
                                content: Text(l10n.applyingChanges),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          } catch (_) {}

                          TagManager.clearCache();

                          final commonTags =
                              await batchTagManager.findCommonTags(selectedFiles);

                          int tagsAdded = 0;
                          int tagsRemoved = 0;

                          for (final filePath in selectedFiles) {
                            AppLogger.info(
                                '[ManageTags][BatchDialog] Processing file',
                                error:
                                    'filePath=$filePath selectedTags=$selectedTags commonTags=$commonTags');
                            final existingTags =
                                await TagManager.getTags(filePath);

                            final Set<String> originalTagsSet =
                                Set.from(existingTags);
                            final Set<String> currentTagsSet =
                                Set.from(selectedTags);
                            final Set<String> commonTagsSet =
                                Set.from(commonTags);

                            final updatedTags =
                                Set<String>.from(originalTagsSet);

                            final commonTagsToRemove =
                                commonTagsSet.difference(currentTagsSet);
                            updatedTags.removeAll(commonTagsToRemove);
                            tagsRemoved += commonTagsToRemove.length;

                            final tagsToAdd =
                                currentTagsSet.difference(originalTagsSet);
                            updatedTags.addAll(tagsToAdd);
                            tagsAdded += tagsToAdd.length;

                            await TagManager.setTags(
                                filePath, updatedTags.toList());

                            try {
                              for (String tag in commonTagsToRemove) {
                                bloc.add(RemoveTagFromFile(filePath, tag));
                              }
                              for (String tag in tagsToAdd) {
                                bloc.add(AddTagToFile(filePath, tag));
                              }
                            } catch (_) {}
                          }

                          refreshParentUIBatch();
                          AppLogger.info(
                              '[ManageTags][BatchDialog] Save completed',
                              error:
                                  'selectedFiles=$selectedFiles tagsAdded=$tagsAdded tagsRemoved=$tagsRemoved');

                          try {
                            scaffoldMessenger.showSnackBar(
                              SnackBar(
                                content: Text(l10n.tagsUpdated(
                                    selectedFiles.length,
                                    tagsAdded,
                                    tagsRemoved)),
                              ),
                            );
                            navigator.pop();
                          } catch (_) {}
                        } catch (e) {
                          AppLogger.error(
                            '[ManageTags][BatchDialog] Save failed',
                            error: 'selectedFiles=$selectedFiles error=$e',
                          );
                          debugPrint('Error processing batch tags: $e');
                          try {
                            scaffoldMessenger.showSnackBar(
                              SnackBar(
                                  content: Text('Error processing tags: $e')),
                            );
                          } catch (_) {}
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        textStyle: const TextStyle(fontSize: 16),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                      child: Text(
                          AppLocalizations.of(context)!.save.toUpperCase()),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  });
}

/// Dialog for managing all tags
void showManageTagsDialog(
    BuildContext context, List<String> allTags, String currentPath,
    {List<String>? selectedFiles}) {
  if (selectedFiles != null && selectedFiles.isNotEmpty) {
    showRemoveTagsDialog(context, selectedFiles);
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Please select files to remove tags'),
      duration: Duration(seconds: 2),
    ),
  );
}

/// Shows dialog to remove tags from multiple files
void showRemoveTagsDialog(BuildContext context, List<String> filePaths) {
  void refreshParentUIRemoveTags() {
    TagManager.clearCache();

    try {
      if (filePaths.isNotEmpty) {
        for (final file in filePaths) {
          TagManager.instance.notifyTagChanged("preserve_scroll:$file");
        }
      }
    } catch (_) {}
  }

  showDialog(
    context: context,
    builder: (context) => RemoveTagsChipDialog(
      filePaths: filePaths,
      onTagsRemoved: () {
        refreshParentUIRemoveTags();
      },
    ),
  );
}

/// A stateful dialog for removing tags from multiple files at once
class RemoveTagsChipDialog extends StatefulWidget {
  final List<String> filePaths;
  final VoidCallback onTagsRemoved;

  const RemoveTagsChipDialog(
      {Key? key, required this.filePaths, required this.onTagsRemoved})
      : super(key: key);

  @override
  State<RemoveTagsChipDialog> createState() => _RemoveTagsChipDialogState();
}

class _RemoveTagsChipDialogState extends State<RemoveTagsChipDialog> {
  final Map<String, Set<String>> _fileTagMap = {};
  final Set<String> _commonTags = {};
  final Set<String> _selectedTagsToRemove = {};
  bool _isLoading = true;
  bool _isRemoving = false;

  @override
  void initState() {
    super.initState();
    _loadTagsForFiles();
  }

  Future<void> _loadTagsForFiles() async {
    setState(() => _isLoading = true);

    try {
      for (final filePath in widget.filePaths) {
        final tags = await TagManager.getTags(filePath);
        _fileTagMap[filePath] = tags.toSet();

        if (_fileTagMap.keys.length == 1) {
          _commonTags.addAll(tags);
        } else {
          _commonTags.retainAll(tags.toSet());
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error loading tags for multiple files: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _toggleTagSelection(String tag) {
    setState(() {
      if (_selectedTagsToRemove.contains(tag)) {
        _selectedTagsToRemove.remove(tag);
      } else {
        _selectedTagsToRemove.add(tag);
      }
    });
  }

  Future<void> _removeSelectedTags() async {
    if (_selectedTagsToRemove.isEmpty) {
      RouteUtils.safePopDialog(context);
      return;
    }

    setState(() => _isRemoving = true);

    // Pre-extract all context-dependent values before async gap
    final bloc = BlocProvider.of<FolderListBloc>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      try {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.applyingChanges),
            duration: const Duration(seconds: 1),
          ),
        );
      } catch (_) {}

      for (final tagToRemove in _selectedTagsToRemove) {
        await BatchTagManager.removeTagFromFilesStatic(
            widget.filePaths, tagToRemove);

        try {
          for (final filePath in widget.filePaths) {
            bloc.add(RemoveTagFromFile(filePath, tagToRemove));
          }
        } catch (_) {}
      }

      try {
        navigator.pop();

        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              'Đã xóa ${_selectedTagsToRemove.length} thẻ khỏi ${widget.filePaths.length} tệp',
            ),
          ),
        );

        TagManager.clearCache();

        for (final file in widget.filePaths) {
          TagManager.instance.notifyTagChanged("preserve_scroll:$file");
        }

        widget.onTagsRemoved();
      } catch (_) {}
    } catch (e) {
      debugPrint('Error removing tags: $e');
      try {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Lỗi khi xóa thẻ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } catch (_) {}
    } finally {
      if (mounted) {
        setState(() => _isRemoving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final double dialogWidth = screenSize.width * 0.5;
    final double dialogHeight = screenSize.height * 0.6;

    return BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: AlertDialog(
        title: Text(
          'Xóa thẻ cho ${widget.filePaths.length} tệp',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        content: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(
            maxWidth: dialogWidth,
            maxHeight: dialogHeight,
            minHeight: dialogHeight * 0.7,
          ),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isLoading)
                const Expanded(
                  child: Center(
                      child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text("Đang tải thẻ...")
                    ],
                  )),
                )
              else if (_commonTags.isEmpty && !_isLoading)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(PhosphorIconsLight.info,
                            size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'Không có thẻ chung nào giữa các tệp đã chọn',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: Colors.grey.shade600),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_selectedTagsToRemove.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: Text(
                              AppLocalizations.of(context)!
                                  .tagsSelected(_selectedTagsToRemove.length),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.bold,
                              )),
                        ),
                      const Text(
                        'Chọn thẻ chung để xóa:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? Colors.grey[800]
                                    : Colors.grey[100],
                            borderRadius: BorderRadius.circular(16.0),
                            border: Border.all(
                              color: Colors.grey.withValues(alpha: 0.2),
                            ),
                          ),
                          child: ListView(
                            padding: const EdgeInsets.all(8),
                            children: _commonTags.map((tag) {
                              final isSelected =
                                  _selectedTagsToRemove.contains(tag);
                              return CheckboxListTile(
                                title: Text(tag),
                                value: isSelected,
                                onChanged: (_) => _toggleTagSelection(tag),
                                activeColor:
                                    Theme.of(context).colorScheme.error,
                                checkColor: Colors.white,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                dense: true,
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed:
                _isRemoving ? null : () => RouteUtils.safePopDialog(context),
            style: TextButton.styleFrom(
              textStyle: const TextStyle(fontSize: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: Text(AppLocalizations.of(context)!.cancel.toUpperCase()),
          ),
          ElevatedButton(
            onPressed: _selectedTagsToRemove.isEmpty ||
                    _isRemoving ||
                    _commonTags.isEmpty
                ? null
                : _removeSelectedTags,
            style: ElevatedButton.styleFrom(
              textStyle: const TextStyle(fontSize: 16),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            child: _isRemoving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(AppLocalizations.of(context)!.removeTag.toUpperCase()),
          ),
        ],
      ),
    );
  }
}
