import 'package:cb_file_manager/ui/widgets/tag_input_helpers.dart';
export 'package:cb_file_manager/ui/widgets/tag_input_helpers.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_thumbnail_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_hierarchy_manager.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/tags/batch_tag_manager.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import 'package:cb_file_manager/ui/widgets/resizable_dialog.dart';
import 'package:cb_file_manager/ui/widgets/tag_browse_section.dart';
import 'package:cb_file_manager/ui/widgets/tag_chips_field.dart';
import 'package:cb_file_manager/ui/widgets/chips_input.dart';
import 'package:cb_file_manager/ui/widgets/tag_management_section.dart';
import 'package:cb_file_manager/utils/app_logger.dart';
import '../../utils/route.dart';

/// Dialog for adding a tag to a file
void showAddTagToFileDialog(BuildContext context, String filePath) {
  AppLogger.info('[ManageTags][Dialog] Opening dialog for $filePath');

  void refreshParentUI(String filePath, {bool preserveScroll = true}) {
    TagManager.clearCache();
    if (preserveScroll) {
      TagManager.instance.notifyTagChanged("preserve_scroll:$filePath");
    } else {
      TagManager.instance.notifyTagChanged(filePath);
    }
    TagManager.instance.notifyTagChanged(filePath);
    TagManager.instance.notifyTagChanged("global:tag_updated");
  }

  RouteUtils.showAcrylicDialog(
    context: context,
    builder: (dialogContext) {
      AppLogger.debug('[ManageTags][Dialog] showDialog builder for $filePath');
      return _SingleFileTagDialog(filePath: filePath);
    },
  ).then((result) {
    if (result == true) {
      AppLogger.info(
        '[ManageTags][Dialog] Refresh triggered after save',
        error: 'filePath=$filePath',
      );
      refreshParentUI(filePath);
      if (context.mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppToast.success(context, l10n.tagsSavedSuccessfully);
      }
    }
  });
}

class _SingleFileTagDialog extends StatefulWidget {
  final String filePath;

  const _SingleFileTagDialog({required this.filePath});

  @override
  State<_SingleFileTagDialog> createState() => _SingleFileTagDialogState();
}

class _SingleFileTagDialogState extends State<_SingleFileTagDialog> {
  final _inputKey = GlobalKey<ChipsInputState<String>>();
  List<String> _originalTags = <String>[];
  List<String> _selectedTags = <String>[];
  List<String> _tagSuggestions = <String>[];
  String _draftTagText = '';

  /// Parent tag whose inline chip contains the child draft.
  /// While set, the draft is only the child name and every submit composes
  /// "parent:child" — so a run of children goes in without retyping the
  /// parent once.
  String? _scopeParent;
  bool _isLoading = true;
  bool _isSaving = false;
  Timer? _debounceTimer;
  int _suggestionGeneration = 0;
  final _thumbnailManager = TagThumbnailManager.instance;
  final _hierarchyManager = TagHierarchyManager.instance;

  @override
  void initState() {
    super.initState();
    _loadTags();
    _initManagers();
  }

  Future<void> _initManagers() async {
    await Future.wait([
      _thumbnailManager.initialize(),
      _hierarchyManager.initialize(),
    ]);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _suggestionGeneration++;
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTags() async {
    AppLogger.info(
      '[ManageTags][Dialog] Loading tags',
      error: 'filePath=${widget.filePath}',
    );
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
      AppLogger.info(
        '[ManageTags][Dialog] Loaded tags',
        error: 'filePath=${widget.filePath} tags=$tags',
      );
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

  /// The text the suggestion engine and the hierarchy parser see. Inside a
  /// scope the pill supplies the parent, so the draft carries only the child.
  String _scopedQuery(String text) {
    final draft = text.trim();
    final scope = _scopeParent;
    return scope == null ? draft : '$scope:$draft';
  }

  void _onScopeChanged(String? parent) {
    setState(() {
      _scopeParent = parent;
      _draftTagText = '';
      _tagSuggestions = <String>[];
    });
    // Entering a scope leaves an empty draft, which still resolves to
    // "parent:" and therefore lists that parent's existing children.
    _updateTagSuggestions('');
  }

  Future<void> _updateTagSuggestions(String text) async {
    _debounceTimer?.cancel();
    final generation = ++_suggestionGeneration;
    final query = _scopedQuery(text);
    if (mounted) setState(() => _tagSuggestions = []);

    if (query.isEmpty) {
      if (!mounted) return;
      setState(() {
        _tagSuggestions = <String>[];
      });
      return;
    }

    // Debounce 100ms
    _debounceTimer = Timer(const Duration(milliseconds: 100), () async {
      final suggestions = await computeTagSuggestions(
        query,
        hierarchyManager: _hierarchyManager,
        isSelected: _containsTag,
      );
      if (!mounted || generation != _suggestionGeneration) return;
      setState(() {
        _tagSuggestions = suggestions;
      });
    });
  }

  bool _containsTag(String tag) {
    final normalizedTag = tag.trim().toLowerCase();
    return _selectedTags.any((selectedTag) {
      return selectedTag.trim().toLowerCase() == normalizedTag;
    });
  }

  /// Handles picking a suggestion from the autocomplete overlay.
  ///
  /// When the user is typing in "parent:child" context (the draft already has a
  /// colon), the suggestion is the child tag — reconstruct the full
  /// "parent:child" input so the hierarchy relationship is created. Otherwise
  /// add the suggestion as-is.
  void _onSuggestionSelected(String suggestion) {
    final scope = _scopeParent;
    if (scope != null) {
      _addTag('$scope:$suggestion');
      return;
    }
    _addTag(resolvePickedSuggestion(_draftTagText, suggestion));
  }

  void _addTag(String rawTag) {
    final tag = rawTag.trim();
    _inputKey.currentState?.clearDraft();
    if (tag.isEmpty) {
      _draftTagText = '';
      return;
    }

    // Handle parent:child format
    if (tag.contains(':')) {
      _addHierarchyTags(tag);
      return;
    }

    if (_containsTag(tag)) {
      _draftTagText = '';
      return;
    }

    setState(() {
      _selectedTags = <String>[..._selectedTags, tag];
      _draftTagText = '';
      _tagSuggestions = <String>[];
    });
    AppLogger.info(
      '[ManageTags][Dialog] Tag added',
      error: 'filePath=${widget.filePath} tag=$tag',
    );
  }

  /// Parse and add tags in parent:child format.
  /// Creates hierarchy relationships and adds all tags to the selection.
  void _addHierarchyTags(String input) {
    final parsed = parseHierarchyInput(input);
    if (parsed == null || !parsed.isValid) return;

    final parentName = parsed.parentName;
    final childNames = parsed.childNames;

    // Only add child tags to the file's tag list.
    // The parent tag is created/ensured in the tag store via
    // createHierarchyRelationships but is NOT automatically assigned to the
    // file — the user typed "parent:child" to create a child under a parent,
    // not to assign the parent itself.
    final tagsToAdd = childNames
        .where((child) => !_containsTag(child))
        .toList(growable: false);

    if (tagsToAdd.isEmpty) {
      _draftTagText = '';
      return;
    }

    setState(() {
      _selectedTags = <String>[..._selectedTags, ...tagsToAdd];
      _draftTagText = '';
      _tagSuggestions = <String>[];
    });

    // Create hierarchy relationships asynchronously (fire and forget)
    createHierarchyRelationships(_hierarchyManager, parentName, childNames);

    AppLogger.info(
      '[ManageTags][Dialog] Hierarchy tags added',
      error:
          'filePath=${widget.filePath} parent=$parentName children=$childNames',
    );
  }

  void _removeTag(String tag) {
    final normalized = tag.trim().toLowerCase();
    setState(() {
      _selectedTags = _selectedTags
          .where((value) => value.trim().toLowerCase() != normalized)
          .toList();
    });
    AppLogger.info(
      '[ManageTags][Dialog] Tag removed',
      error: 'filePath=${widget.filePath} tag=$tag',
    );
  }

  /// Submits the typed draft, composing "parent:child" when the field is
  /// scoped to a parent.
  void _submitDraft(String value) {
    if (value.trim().isEmpty) {
      return;
    }
    _addTag(_scopedQuery(value));
  }

  void _commitDraftTag() {
    _submitDraft(_draftTagText);
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

    AppLogger.info(
      '[ManageTags][Dialog] Save pressed',
      error:
          'filePath=${widget.filePath} selectedTags=$_selectedTags draftTagText=$_draftTagText',
    );

    setState(() {
      _isSaving = true;
    });

    try {
      _commitDraftTag();

      final tagsToPersist = List<String>.from(_selectedTags);
      AppLogger.info(
        '[ManageTags][Dialog] Persisting tags',
        error: 'filePath=${widget.filePath} tags=$tagsToPersist',
      );

      if (_hasChanges || _draftTagText.trim().isNotEmpty) {
        final success = await TagManager.setTags(
          widget.filePath,
          tagsToPersist,
        );
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
      AppToast.error(context, l10n.errorSavingTags(error.toString()));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Widget _buildTagInputSection(AppLocalizations l10n) {
    final scope = _scopeParent;
    return _buildSectionCard(
      icon: PhosphorIconsLight.pencilSimpleLine,
      title: l10n.addTag,
      subtitle: scope != null ? l10n.addingUnderTag(scope) : l10n.tagInputHelp,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TagChipsField(
            fieldKey: _inputKey,
            tags: _selectedTags,
            suggestions: _tagSuggestions,
            scopeParent: scope,
            onScopeChanged: _onScopeChanged,
            onSuggestionSelected: _onSuggestionSelected,
            hintText: l10n.enterTagName,
            onTextChanged: (value) {
              _draftTagText = value;
              _updateTagSuggestions(value);
            },
            onSubmitted: _submitDraft,
            onRemoved: _removeTag,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget child,
    bool expandChild = false,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: CbDecorations.card(context, radius: 20),
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
                child: Icon(icon, size: 18, color: theme.colorScheme.primary),
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
          if (expandChild) Expanded(child: child) else child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return ResizableDialog(
      prefsKeyPrefix: 'manage_tags_dialog',
      minSize: const Size(460, 420),
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
            decoration: CbDecorations.card(context, radius: 14),
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
      contentBuilder: (context, dialogSize) {
        if (_isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        // The input + quick picks keep their natural height (scrolling on their
        // own when the dialog is short) and the browse section takes all the
        // room that is left, so the tag list always runs down to the bottom
        // edge of the dialog and grows when the dialog is resized.
        return LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxHeight;
            final browseFloor = math.min(220.0, available * 0.45);
            final topMaxHeight = math.max(0.0, available - browseFloor - 18);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: topMaxHeight),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTagInputSection(l10n),
                        const SizedBox(height: 18),
                        _buildSectionCard(
                          icon: PhosphorIconsLight.sparkle,
                          title: 'Quick Picks',
                          subtitle:
                              'Choose from popular and recently used tags',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              PopularTagsWidget(onTagSelected: _addTag),
                              const SizedBox(height: 18),
                              RecentTagsWidget(onTagSelected: _addTag),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: _buildSectionCard(
                    icon: PhosphorIconsLight.treeStructure,
                    title: l10n.allTags,
                    subtitle:
                        'Browse the tag tree — expand a parent to pick its children.',
                    expandChild: true,
                    child: TagBrowseSection(
                      selectedTags: _selectedTags,
                      onTagSelected: _addTag,
                      onTagDeselected: _removeTag,
                      fillHeight: true,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
      actions: [
        TextFieldTapRegion(
          child: TextButton(
            onPressed: _isSaving
                ? null
                : () {
                    AppLogger.info(
                      '[ManageTags][Dialog] Close pressed',
                      error: 'filePath=${widget.filePath}',
                    );
                    Navigator.of(context, rootNavigator: true).pop(false);
                  },
            style: TextButton.styleFrom(
              textStyle: const TextStyle(fontSize: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: Text(l10n.close.toUpperCase()),
          ),
        ),
        TextFieldTapRegion(
          child: ElevatedButton(
            onPressed: _isSaving ? null : _save,
            style: ElevatedButton.styleFrom(
              textStyle: const TextStyle(fontSize: 16),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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

  RouteUtils.showAcrylicDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
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
                  CbSelect<String>(
                    expand: true,
                    value: selectedTag,
                    placeholder: AppLocalizations.of(
                      context,
                    )!.selectTagToRemove,
                    items: [
                      for (final tag in tags)
                        CbSelectItem<String>(value: tag, label: tag),
                    ],
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
                child: Text(AppLocalizations.of(context)!.cancel.toUpperCase()),
              ),
              TextButton(
                onPressed: () async {
                  if (selectedTag != null) {
                    // Pre-extract all context-dependent values before async gap
                    final l10n = AppLocalizations.of(context)!;
                    final bloc = BlocProvider.of<FolderListBloc>(
                      context,
                      listen: false,
                    );
                    final toast = AppToast.capture(context);
                    final navigator = Navigator.of(context);

                    try {
                      await TagManager.removeTag(filePath, selectedTag!);
                      TagManager.clearCache();

                      try {
                        bloc.add(RemoveTagFromFile(filePath, selectedTag!));
                      } catch (_) {}

                      TagManager.instance.notifyTagChanged(
                        "tag_only:$filePath",
                      );

                      try {
                        toast.success(l10n.tagDeleted(selectedTag!));
                        navigator.pop();
                      } catch (_) {}
                    } catch (e) {
                      try {
                        toast.error(l10n.errorDeletingTag(e.toString()));
                      } catch (_) {}
                    }
                  } else {
                    try {
                      Navigator.of(context).pop();
                    } catch (_) {}
                  }
                },
                child: Text(
                  AppLocalizations.of(context)!.removeTag.toUpperCase(),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Dialog for batch adding tags
void showBatchAddTagDialog(BuildContext context, List<String> selectedFiles) {
  final focusNode = FocusNode();
  final inputKey = GlobalKey<ChipsInputState<String>>();
  List<String> tagSuggestions = [];
  List<String> selectedTags = [];
  String draftTagText = '';
  int suggestionGeneration = 0;

  /// Parent tag the input is scoped to — see _SingleFileTagDialogState.
  String? scopeParent;
  bool isSaving = false;

  final thumbnailManager = TagThumbnailManager.instance;
  final hierarchyManager = TagHierarchyManager.instance;
  Future.wait([thumbnailManager.initialize(), hierarchyManager.initialize()]);

  AppLogger.info(
    '[ManageTags][BatchDialog] Opening batch dialog',
    error: 'selectedFiles=$selectedFiles',
  );

  /// Inside a scope the pill supplies the parent, so the draft carries only
  /// the child name.
  String scopedQuery(String text) {
    final draft = text.trim();
    final scope = scopeParent;
    return scope == null ? draft : '$scope:$draft';
  }

  Future<void> updateTagSuggestions(String text) async {
    final generation = ++suggestionGeneration;
    final suggestions = await computeTagSuggestions(
      scopedQuery(text),
      hierarchyManager: hierarchyManager,
      isSelected: selectedTags.contains,
    );
    if (generation == suggestionGeneration) tagSuggestions = suggestions;
  }

  /// Handles "parent:child1,child2" input by adding the parent + children to
  /// the selection and creating the hierarchy relationships in the background.
  /// Returns true when the input was hierarchy input (and was handled).
  bool addHierarchyTags(String input) {
    final parsed = parseHierarchyInput(input);
    if (parsed == null || !parsed.isValid) return false;

    // Only add child tags to the selection; the parent is ensured in the
    // tag store via createHierarchyRelationships but NOT auto-assigned.
    final tagsToAdd = parsed.childNames
        .where((child) => !selectedTags.contains(child))
        .toList(growable: false);

    selectedTags.addAll(tagsToAdd);
    inputKey.currentState?.clearDraft();
    draftTagText = '';
    tagSuggestions = [];

    createHierarchyRelationships(
      hierarchyManager,
      parsed.parentName,
      parsed.childNames,
    );

    AppLogger.info(
      '[ManageTags][BatchDialog] Hierarchy tags added',
      error: 'parent=${parsed.parentName} children=${parsed.childNames}',
    );
    return true;
  }

  void addTag(String tag) {
    final trimmed = tag.trim();
    if (trimmed.isEmpty) return;

    // parent:child syntax — create hierarchy instead of a flat tag.
    if (trimmed.contains(':')) {
      if (addHierarchyTags(trimmed)) return;
    }

    if (!selectedTags.contains(trimmed)) {
      selectedTags.add(trimmed);
      inputKey.currentState?.clearDraft();
      draftTagText = '';
    }
  }

  /// Submits the typed draft, composing "parent:child" while scoped.
  void submitDraft(String value) {
    if (value.trim().isEmpty) {
      return;
    }
    addTag(scopedQuery(value));
    tagSuggestions = [];
  }

  void commitDraftTag() {
    submitDraft(draftTagText);
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
    AppLogger.info(
      '[ManageTags][BatchDialog] Loaded common tags',
      error: 'selectedFiles=$selectedFiles commonTags=$commonTags',
    );

    RouteUtils.showAcrylicDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            void refreshSuggestions(String value) {
              // computeTagSuggestions is async; without repainting when it
              // resolves the overlay lags a keystroke behind, and a scope
              // change would show no children at all.
              updateTagSuggestions(value).then((_) {
                if (context.mounted) setState(() {});
              });
            }

            void handleTextChange(String value) {
              draftTagText = value;
              setState(() => tagSuggestions = []);
              refreshSuggestions(value);
            }

            void handleScopeChange(String? parent) {
              setState(() {
                scopeParent = parent;
                draftTagText = '';
                tagSuggestions = [];
              });
              refreshSuggestions('');
            }

            void handleTagSubmit(String value) {
              if (value.trim().isNotEmpty) {
                setState(() {
                  submitDraft(value);
                });
                AppLogger.info(
                  '[ManageTags][BatchDialog] Tag submitted',
                  error: 'selectedFiles=$selectedFiles tag=$value',
                );
              }
            }

            void handleTagSelected(String tag) {
              // In the batch dialog, tapping a popular/recent tag should add it
              // to the input (like the single-file dialog), not open a search
              // tab. Opening a search tab here is unexpected for the user.
              setState(() {
                addTag(tag);
                tagSuggestions = [];
              });
              AppLogger.info(
                '[ManageTags][BatchDialog] Quick tag added',
                error: 'selectedFiles=$selectedFiles tag=$tag',
              );
            }

            void handleTagDeselected(String tag) {
              final normalized = tag.trim().toLowerCase();
              setState(() {
                selectedTags.removeWhere(
                  (value) => value.trim().toLowerCase() == normalized,
                );
              });
            }

            return ResizableDialog(
              prefsKeyPrefix: 'batch_tags_dialog',
              minSize: const Size(460, 420),
              title: Text(
                AppLocalizations.of(
                  context,
                )!.batchAddTags(selectedFiles.length),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              contentBuilder: (context, dialogSize) {
                final browseHeight = (dialogSize.height - 510).clamp(
                  160.0,
                  900.0,
                );
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Focus(
                        focusNode: focusNode,
                        child: TagChipsField(
                          fieldKey: inputKey,
                          tags: selectedTags,
                          suggestions: tagSuggestions,
                          scopeParent: scopeParent,
                          onScopeChanged: handleScopeChange,
                          onSuggestionSelected: (tag) {
                            setState(() {
                              final scope = scopeParent;
                              addTag(
                                scope != null
                                    ? '$scope:$tag'
                                    : resolvePickedSuggestion(
                                        draftTagText,
                                        tag,
                                      ),
                              );
                              tagSuggestions = [];
                            });
                          },
                          onTextChanged: handleTextChange,
                          onSubmitted: handleTagSubmit,
                          onRemoved: handleTagDeselected,
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
                                    handleTagDeselected(tag);
                                  },
                                  deleteIcon: const Icon(
                                    PhosphorIconsLight.x,
                                    size: 16,
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      const SizedBox(height: 24),
                      PopularTagsWidget(onTagSelected: handleTagSelected),
                      const SizedBox(height: 24),
                      RecentTagsWidget(onTagSelected: handleTagSelected),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Icon(
                            PhosphorIconsLight.treeStructure,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            AppLocalizations.of(context)!.allTags,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TagBrowseSection(
                        selectedTags: selectedTags,
                        onTagSelected: handleTagSelected,
                        onTagDeselected: handleTagDeselected,
                        maxHeight: browseHeight,
                      ),
                    ],
                  ),
                );
              },
              actions: [
                TextFieldTapRegion(
                  child: TextButton(
                    onPressed: isSaving
                        ? null
                        : () {
                            RouteUtils.safePopDialog(context);
                          },
                    style: TextButton.styleFrom(
                      textStyle: const TextStyle(fontSize: 16),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.cancel.toUpperCase(),
                    ),
                  ),
                ),
                TextFieldTapRegion(
                  child: ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            AppLogger.info(
                              '[ManageTags][BatchDialog] Save pressed',
                              error:
                                  'selectedFiles=$selectedFiles selectedTags=$selectedTags draftTagText=$draftTagText',
                            );
                            final l10n = AppLocalizations.of(context)!;
                            // Persistence happens through TagManager; UI refresh is
                            // driven by the coalesced tag-change notification fired in
                            // refreshParentUIBatch(). No bloc lookup is needed here.
                            final toast = AppToast.capture(context);
                            final navigator = Navigator.of(context);

                            try {
                              setState(() {
                                commitDraftTag();
                                isSaving = true;
                              });
                              try {
                                toast.info(l10n.applyingChanges);
                              } catch (_) {}

                              TagManager.clearCache();

                              final commonTags = await batchTagManager
                                  .findCommonTags(selectedFiles);

                              int tagsAdded = 0;
                              int tagsRemoved = 0;

                              // Read every file's existing tags in a single batched
                              // round-trip instead of awaiting getTags() one file at
                              // a time — the per-file await was a big part of the UI
                              // stall on large selections.
                              final existingTagsByFile =
                                  await TagManager.getTagsForFiles(
                                    selectedFiles,
                                  );

                              final Set<String> currentTagsSet =
                                  Set<String>.from(selectedTags);
                              final Set<String> commonTagsSet =
                                  Set<String>.from(commonTags);
                              final commonTagsToRemove = commonTagsSet
                                  .difference(currentTagsSet);

                              for (final filePath in selectedFiles) {
                                final existingTags =
                                    existingTagsByFile[filePath] ??
                                    const <String>[];

                                final Set<String> originalTagsSet =
                                    Set<String>.from(existingTags);
                                final updatedTags = Set<String>.from(
                                  originalTagsSet,
                                );

                                updatedTags.removeAll(commonTagsToRemove);
                                tagsRemoved += originalTagsSet
                                    .intersection(commonTagsToRemove)
                                    .length;

                                final tagsToAdd = currentTagsSet.difference(
                                  originalTagsSet,
                                );
                                updatedTags.addAll(tagsToAdd);
                                tagsAdded += tagsToAdd.length;

                                // Suppress the per-file tag-change event; a single
                                // coalesced refresh is fired below via
                                // refreshParentUIBatch(). Otherwise each file would
                                // trigger a full folder-list reload.
                                await TagManager.setTags(
                                  filePath,
                                  updatedTags.toList(),
                                  notify: false,
                                );
                              }

                              refreshParentUIBatch();
                              AppLogger.info(
                                '[ManageTags][BatchDialog] Save completed',
                                error:
                                    'selectedFiles=$selectedFiles tagsAdded=$tagsAdded tagsRemoved=$tagsRemoved',
                              );

                              try {
                                toast.success(
                                  l10n.tagsUpdated(
                                    selectedFiles.length,
                                    tagsAdded,
                                    tagsRemoved,
                                  ),
                                );
                                navigator.pop();
                              } catch (_) {}
                            } catch (e) {
                              AppLogger.error(
                                '[ManageTags][BatchDialog] Save failed',
                                error: 'selectedFiles=$selectedFiles error=$e',
                              );
                              AppLogger.warning(
                                'Error processing batch tags: $e',
                              );
                              try {
                                toast.error(
                                  l10n.batchTagProcessingError(e.toString()),
                                );
                              } catch (_) {}
                            } finally {
                              // Reset the saving flag only if the dialog is still
                              // open (the success path pops it and unmounts).
                              if (context.mounted) {
                                setState(() {
                                  isSaving = false;
                                });
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      textStyle: const TextStyle(fontSize: 16),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    child: isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            AppLocalizations.of(context)!.save.toUpperCase(),
                          ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  });
}

/// Dialog for managing all tags
void showManageTagsDialog(
  BuildContext context,
  List<String> allTags,
  String currentPath, {
  List<String>? selectedFiles,
}) {
  if (selectedFiles != null && selectedFiles.isNotEmpty) {
    showRemoveTagsDialog(context, selectedFiles);
    return;
  }

  final l10n = AppLocalizations.of(context)!;
  AppToast.warning(context, l10n.selectFilesToRemoveTags);
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

  RouteUtils.showAcrylicDialog(
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

  const RemoveTagsChipDialog({
    super.key,
    required this.filePaths,
    required this.onTagsRemoved,
  });

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
      AppLogger.warning('Error loading tags for multiple files: $e');
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
    final toast = AppToast.capture(context);
    final navigator = Navigator.of(context);
    final l10n = AppLocalizations.of(context)!;

    try {
      try {
        toast.info(AppLocalizations.of(context)!.applyingChanges);
      } catch (_) {}

      for (final tagToRemove in _selectedTagsToRemove) {
        await BatchTagManager.removeTagFromFilesStatic(
          widget.filePaths,
          tagToRemove,
        );

        try {
          for (final filePath in widget.filePaths) {
            bloc.add(RemoveTagFromFile(filePath, tagToRemove));
          }
        } catch (_) {}
      }

      try {
        navigator.pop();

        toast.success(
          l10n.removeTagsSuccess(
            _selectedTagsToRemove.length,
            widget.filePaths.length,
          ),
        );

        TagManager.clearCache();

        for (final file in widget.filePaths) {
          TagManager.instance.notifyTagChanged("preserve_scroll:$file");
        }

        widget.onTagsRemoved();
      } catch (_) {}
    } catch (e) {
      AppLogger.warning('Error removing tags: $e');
      try {
        toast.error(l10n.removeTagsError(e.toString()));
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

    return AlertDialog(
      title: Text(
        AppLocalizations.of(
          context,
        )!.removeTagsFromFilesTitle(widget.filePaths.length),
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(AppLocalizations.of(context)!.loadingTags),
                    ],
                  ),
                ),
              )
            else if (_commonTags.isEmpty && !_isLoading)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        PhosphorIconsLight.info,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        AppLocalizations.of(
                          context,
                        )!.noCommonTagsAcrossSelectedFiles,
                        style: Theme.of(context).textTheme.titleMedium
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
                          AppLocalizations.of(
                            context,
                          )!.tagsSelected(_selectedTagsToRemove.length),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    Text(
                      AppLocalizations.of(context)!.selectCommonTagsToRemove,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Container(
                        decoration: CbDecorations.card(context, radius: 16),
                        child: ListView(
                          padding: const EdgeInsets.all(8),
                          children: _commonTags.map((tag) {
                            final isSelected = _selectedTagsToRemove.contains(
                              tag,
                            );
                            return CheckboxListTile(
                              title: Text(tag),
                              value: isSelected,
                              onChanged: (_) => _toggleTagSelection(tag),
                              activeColor: Theme.of(context).colorScheme.error,
                              checkColor: Colors.white,
                              controlAffinity: ListTileControlAffinity.leading,
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
          onPressed: _isRemoving
              ? null
              : () => RouteUtils.safePopDialog(context),
          style: TextButton.styleFrom(
            textStyle: const TextStyle(fontSize: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: Text(AppLocalizations.of(context)!.cancel.toUpperCase()),
        ),
        ElevatedButton(
          onPressed:
              _selectedTagsToRemove.isEmpty ||
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
    );
  }
}
