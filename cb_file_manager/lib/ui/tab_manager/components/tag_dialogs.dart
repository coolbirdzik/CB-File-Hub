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

  void refreshParentUI(BuildContext dialogContext, String filePath,
      {bool preserveScroll = true}) {
    TagManager.clearCache();
    if (preserveScroll) {
      TagManager.instance.notifyTagChanged("preserve_scroll:$filePath");
    } else {
      TagManager.instance.notifyTagChanged(filePath);
    }
    TagManager.instance.notifyTagChanged(filePath);
    TagManager.instance.notifyTagChanged("global:tag_updated");
  }

  late TagManagementSection tagSection;
  bool tagSectionReady = false;

  showDialog(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: AlertDialog(
              title: Text(
                AppLocalizations.of(context)!.addTag,
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              content: Container(
                width: double.maxFinite,
                constraints: BoxConstraints(
                  maxWidth: dialogWidth,
                  maxHeight: dialogHeight,
                  minHeight: dialogHeight * 0.7,
                ),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: SingleChildScrollView(
                  child: TagManagementSection(
                    filePath: filePath,
                    onTagsUpdated: () {
                      refreshParentUI(context, filePath);
                    },
                    onPendingChangesChanged: () {
                      setState(() {});
                    },
                    onSectionReady: (section) {
                      tagSection = section;
                      tagSectionReady = true;
                    },
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context, rootNavigator: true).pop();
                  },
                  style: TextButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 16),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                  child:
                      Text(AppLocalizations.of(context)!.close.toUpperCase()),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final l10n = AppLocalizations.of(context)!;
                    debugPrint(
                        'SAVE: pressed, tagSectionReady=$tagSectionReady');

                    if (!tagSectionReady) {
                      debugPrint('SAVE: section not ready');
                      return;
                    }

                    // Pre-extract all context-dependent values before async gap
                    final navigator = Navigator.of(context, rootNavigator: true);
                    final scaffoldMessenger = ScaffoldMessenger.of(context);

                    try {
                      debugPrint('SAVE: calling saveChanges');
                      await tagSection.saveChanges();
                      debugPrint('SAVE: save done, closing');
                      // ignore: use_build_context_synchronously
                      refreshParentUI(context, filePath);
                      try {
                        navigator.pop();
                      } catch (_) {}
                    } catch (e) {
                      debugPrint('SAVE: error=$e');
                      try {
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            content: Text(l10n.errorSavingTags(e.toString())),
                            backgroundColor: Colors.red,
                          ),
                        );
                      } catch (_) {}
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 16),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                  child: Text(AppLocalizations.of(context)!.save.toUpperCase()),
                ),
              ],
            ),
          );
        },
      );
    },
  );
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
                      final bloc = BlocProvider.of<FolderListBloc>(context, listen: false);
                      final scaffoldMessenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(context);

                      try {
                        await TagManager.removeTag(filePath, selectedTag!);
                        TagManager.clearCache();

                        try {
                          bloc.add(RemoveTagFromFile(filePath, selectedTag!));
                        } catch (_) {}

                        TagManager.instance.notifyTagChanged("tag_only:$filePath");

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
                              content: Text(l10n.errorDeletingTag(e.toString())),
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

  final Size screenSize = MediaQuery.of(context).size;
  final double dialogWidth = screenSize.width * 0.5;
  final double dialogHeight = screenSize.height * 0.6;

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
    }
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

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            void handleTextChange(String value) {
              updateTagSuggestions(value);
              setState(() {});
            }

            void handleTagSubmit(String value) {
              if (value.trim().isNotEmpty) {
                setState(() {
                  addTag(value);
                  tagSuggestions = [];
                });
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
                  TextButton(
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
                  ElevatedButton(
                    onPressed: () async {
                      // Pre-extract all context-dependent values before async gap
                      final l10n = AppLocalizations.of(context)!;
                      final bloc = BlocProvider.of<FolderListBloc>(context, listen: false);
                      final scaffoldMessenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(context);

                      try {
                        try {
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text(l10n.applyingChanges),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        } catch (_) {}

                        TagManager.clearCache();

                        final commonTags = await batchTagManager
                            .findCommonTags(selectedFiles);

                        int tagsAdded = 0;
                        int tagsRemoved = 0;

                        for (final filePath in selectedFiles) {
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

                        try {
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text(l10n.tagsUpdated(
                                  selectedFiles.length, tagsAdded, tagsRemoved)),
                            ),
                          );
                          navigator.pop();
                        } catch (_) {}
                      } catch (e) {
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
                    child:
                        Text(AppLocalizations.of(context)!.save.toUpperCase()),
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
