import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/ui/widgets/chips_input.dart';
import 'package:cb_file_manager/helpers/tags/tag_color_manager.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/utils/app_logger.dart';

class TagManagementSectionController {
  _TagManagementSectionState? _state;

  bool get isAttached => _state != null;

  bool get hasPendingChanges => _state?.hasPendingChanges ?? false;

  int get pendingChangesCount => _state?.pendingChangesCount ?? 0;

  Future<void> saveChanges() async {
    final state = _state;
    if (state == null) {
      debugPrint(
          '[ManageTags][Controller] saveChanges called while controller is detached');
      throw StateError('TagManagementSectionController is not attached');
    }
    debugPrint(
        '[ManageTags][Controller] saveChanges forwarding to state filePath=${state.widget.filePath}');
    await state.saveChanges();
  }

  void discardChanges() {
    debugPrint(
        '[ManageTags][Controller] discardChanges invoked attached=$isAttached');
    _state?.discardChanges();
  }

  void _attach(_TagManagementSectionState state) {
    AppLogger.info(
        '[ManageTags][Controller] Attached to ${state.widget.filePath}');
    debugPrint(
        '[ManageTags][Controller] Attached to filePath=${state.widget.filePath}');
    _state = state;
  }

  void _detach(_TagManagementSectionState state) {
    if (identical(_state, state)) {
      debugPrint(
          '[ManageTags][Controller] Detached from filePath=${state.widget.filePath}');
      _state = null;
    }
  }
}

/// A reusable tag management section that can be used in different places
/// like the file details screen and tag dialogs
class TagManagementSection extends StatefulWidget {
  /// The file path for which to manage tags
  final String filePath;

  /// Callback when tags have been updated
  final VoidCallback? onTagsUpdated;

  /// Whether to show recent tags section
  final bool showRecentTags;

  /// Whether to show popular tags section
  final bool showPopularTags;

  /// Whether to show the header for the file tags section
  final bool showFileTagsHeader;

  /// Initial set of tags
  final List<String>? initialTags;

  /// Callback when pending changes count changes (for badge updates)
  final VoidCallback? onPendingChangesChanged;

  /// Optional controller for imperative access from dialogs or parent widgets.
  final TagManagementSectionController? controller;

  /// Callback when the section's state is ready (after first build)
  final void Function(TagManagementSection section)? onSectionReady;

  const TagManagementSection({
    Key? key,
    required this.filePath,
    this.onTagsUpdated,
    this.showRecentTags = true,
    this.showPopularTags = true,
    this.showFileTagsHeader = true,
    this.initialTags,
    this.onPendingChangesChanged,
    this.controller,
    this.onSectionReady,
  }) : super(key: key);

  @override
  State<TagManagementSection> createState() => _TagManagementSectionState();

  /// Returns true if there are unsaved changes
  bool get hasPendingChanges {
    final state = _TagManagementSectionState.of(this);
    return state?.hasPendingChanges ?? false;
  }

  /// Returns the number of pending changes
  int get pendingChangesCount {
    final state = _TagManagementSectionState.of(this);
    return state?.pendingChangesCount ?? 0;
  }

  /// Saves pending changes to the file
  Future<void> saveChanges() async {
    final state = _TagManagementSectionState.of(this);
    if (state != null) {
      await state.saveChanges();
    }
  }

  /// Discard current tag changes
  void discardChanges() {
    // Find the current state and discard changes
    final state = _TagManagementSectionState.of(this);
    if (state != null) {
      state.discardChanges();
    }
  }
}

class _TagManagementSectionState extends State<TagManagementSection> {
  // A map of states for accessing from static methods
  static final Map<TagManagementSection, _TagManagementSectionState> _states =
      {};

  // Get the state for a given TagManagementSection
  static _TagManagementSectionState? of(TagManagementSection widget) {
    return _states[widget];
  }

  List<String> _tagSuggestions = [];
  List<String> _selectedTags = [];
  List<String> _originalTags = []; // Store original tags to detect changes
  String _draftTagText = '';
  bool _hasPendingChanges = false;
  int _pendingChangesCount = 0;

  /// Public getter: true if there are unsaved changes
  bool get hasPendingChanges => _hasPendingChanges;

  /// Public getter: number of pending changes
  int get pendingChangesCount => _pendingChangesCount;
  late final TagColorManager _colorManager = TagColorManager.instance;

  /// Compute pending changes count and update flags
  void _updatePendingChanges() {
    final added = _selectedTags.where((t) => !_originalTags.contains(t)).length;
    final removed =
        _originalTags.where((t) => !_selectedTags.contains(t)).length;
    _hasPendingChanges = added > 0 || removed > 0;
    _pendingChangesCount = added + removed;
    debugPrint(
        '[ManageTags][Section] Pending changes filePath=${widget.filePath} hasPending=$_hasPendingChanges count=$_pendingChangesCount selected=$_selectedTags original=$_originalTags');
    widget.onPendingChangesChanged?.call();
  }

  @override
  void initState() {
    super.initState();
    // Register this state
    _states[widget] = this;
    widget.controller?._attach(this);
    AppLogger.info('[ManageTags][Section] initState ${widget.filePath}');
    debugPrint('[ManageTags][Section] initState filePath=${widget.filePath}');

    _loadTagData();
    _colorManager.addListener(_handleColorChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onSectionReady?.call(widget);
    });
  }

  @override
  void didUpdateWidget(covariant TagManagementSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget, widget)) {
      debugPrint(
          '[ManageTags][Section] didUpdateWidget oldFilePath=${oldWidget.filePath} newFilePath=${widget.filePath}');
      _states.remove(oldWidget);
      _states[widget] = this;
      if (!identical(oldWidget.controller, widget.controller)) {
        oldWidget.controller?._detach(this);
        widget.controller?._attach(this);
      }
      widget.onSectionReady?.call(widget);
    }
  }

  @override
  void dispose() {
    // Unregister this state
    _states.remove(widget);
    widget.controller?._detach(this);
    debugPrint('[ManageTags][Section] dispose filePath=${widget.filePath}');

    _colorManager.removeListener(_handleColorChanged);
    super.dispose();
  }

  // Xử lý khi màu tag thay đổi
  void _handleColorChanged() {
    if (mounted) {
      setState(() {
        // Chỉ cần rebuild UI
      });
    }
  }

  bool _containsTag(String tag) {
    final normalizedTag = tag.trim().toLowerCase();
    return _selectedTags.any(
      (selectedTag) => selectedTag.trim().toLowerCase() == normalizedTag,
    );
  }

  void _addSelectedTag(
    String tag, {
    bool clearSuggestions = false,
    bool clearDraft = true,
  }) {
    final trimmedTag = tag.trim();
    debugPrint(
        '[ManageTags][Section] _addSelectedTag requested filePath=${widget.filePath} tag="$trimmedTag" clearSuggestions=$clearSuggestions clearDraft=$clearDraft');
    if (trimmedTag.isEmpty || _containsTag(trimmedTag)) {
      debugPrint(
          '[ManageTags][Section] _addSelectedTag ignored filePath=${widget.filePath} tag="$trimmedTag" duplicateOrEmpty=${trimmedTag.isEmpty || _containsTag(trimmedTag)}');
      if (_draftTagText.isNotEmpty || (clearSuggestions && _tagSuggestions.isNotEmpty)) {
        setState(() {
          if (clearDraft) {
            _draftTagText = '';
          }
          if (clearSuggestions) {
            _tagSuggestions = [];
          }
        });
      }
      return;
    }

    setState(() {
      _selectedTags.add(trimmedTag);
      if (clearDraft) {
        _draftTagText = '';
      }
      if (clearSuggestions) {
        _tagSuggestions = [];
      }
    });
    _updatePendingChanges();
  }

  bool _commitDraftTag([String? rawTag]) {
    final draftTag = (rawTag ?? _draftTagText).trim();
    debugPrint(
        '[ManageTags][Section] _commitDraftTag filePath=${widget.filePath} raw="$rawTag" effective="$draftTag"');
    if (draftTag.isEmpty) {
      return false;
    }

    _addSelectedTag(
      draftTag,
      clearSuggestions: true,
      clearDraft: true,
    );
    return true;
  }

  void _loadTagData() async {
    // Use initialTags if provided, otherwise fetch from TagManager
    List<String> currentTags = [];
    AppLogger.debug('[ManageTags][Section] Loading tags for ${widget.filePath}');
    debugPrint('[ManageTags][Section] Loading tag data filePath=${widget.filePath}');

    if (widget.initialTags != null) {
      currentTags = List.from(widget.initialTags!);
    } else {
      try {
        currentTags = await TagManager.getTags(widget.filePath);
      } catch (e) {
        debugPrint(
            '[ManageTags][Section] Loading tags failed filePath=${widget.filePath} error=$e');
        currentTags = [];
      }
    }

    if (mounted) {
      setState(() {
        _selectedTags = List.from(currentTags);
        _originalTags = List.from(currentTags); // Store original state
        _hasPendingChanges = false;
        _pendingChangesCount = 0;
      });
      AppLogger.info(
          '[ManageTags][Section] Loaded ${_selectedTags.length} tags for ${widget.filePath}');
      debugPrint(
          '[ManageTags][Section] Loaded tag data filePath=${widget.filePath} tags=$_selectedTags');
    }
  }

  // Save all changes to file
  Future<void> saveChanges() async {
    AppLogger.info(
        '[ManageTags][Section] saveChanges START ${widget.filePath} pending=$_pendingChangesCount');
    debugPrint(
        '[ManageTags][Section] saveChanges START filePath=${widget.filePath} mounted=$mounted selected=$_selectedTags original=$_originalTags draft="$_draftTagText"');
    if (!mounted) {
      debugPrint(
          '[ManageTags][Section] saveChanges SKIP because widget is not mounted');
      return;
    }

    try {
      _commitDraftTag();

      if (!_hasPendingChanges) {
        AppLogger.warning(
            '[ManageTags][Section] saveChanges skipped because no pending changes for ${widget.filePath}');
        debugPrint(
            '[ManageTags][Section] saveChanges SKIP because there are no pending changes filePath=${widget.filePath}');
        return;
      }

      debugPrint(
          '[ManageTags][Section] Persisting tags filePath=${widget.filePath} tags=$_selectedTags');
      final success = await TagManager.setTags(widget.filePath, _selectedTags);
      if (!success) {
        throw Exception('Failed to persist tags for "${widget.filePath}"');
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _originalTags = List.from(_selectedTags);
        _draftTagText = '';
        _tagSuggestions = [];
        _hasPendingChanges = false;
        _pendingChangesCount = 0;
      });
      widget.onPendingChangesChanged?.call();

      TagManager.clearCache();
      TagManager.instance.notifyTagChanged(widget.filePath);
      TagManager.instance.notifyTagChanged("global:tag_updated");

      await _refreshTags();
      AppLogger.info(
          '[ManageTags][Section] saveChanges DONE ${widget.filePath}');
      debugPrint(
          '[ManageTags][Section] saveChanges DONE filePath=${widget.filePath}');
    } catch (e) {
      AppLogger.error(
        '[ManageTags][Section] saveChanges ERROR ${widget.filePath}',
        error: e,
      );
      debugPrint(
          '[ManageTags][Section] saveChanges ERROR filePath=${widget.filePath} error=$e');
      rethrow;
    }
  }

  // Discard changes and restore original tags
  void discardChanges() {
    debugPrint(
        '[ManageTags][Section] discardChanges filePath=${widget.filePath}');
    setState(() {
      _selectedTags = List.from(_originalTags);
      _draftTagText = '';
      _tagSuggestions = [];
    });
    _updatePendingChanges();
  }

  Future<void> _refreshTags() async {
    debugPrint('[ManageTags][Section] _refreshTags filePath=${widget.filePath}');
    setState(() {
      _tagSuggestions = [];
    });

    if (widget.onTagsUpdated != null) {
      widget.onTagsUpdated!();
    }
  }

  // Keep these methods for manual operations if needed, but not called from UI directly

  Future<void> _updateTagSuggestions(String text) async {
    debugPrint(
        '[ManageTags][Section] _updateTagSuggestions filePath=${widget.filePath} query="$text"');
    if (text.isEmpty) {
      setState(() {
        _tagSuggestions = [];
      });
      return;
    }

    // Get tag suggestions based on current input
    final suggestions = await TagManager.instance.searchTags(text);
    if (mounted) {
      setState(() {
        _tagSuggestions =
            suggestions.where((tag) => !_selectedTags.contains(tag)).toList();
      });
      debugPrint(
          '[ManageTags][Section] Suggestions updated filePath=${widget.filePath} suggestions=$_tagSuggestions');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
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
              borderRadius: BorderRadius.circular(16.0),
              borderSide: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            labelText: AppLocalizations.of(context)!.tagName,
            labelStyle: const TextStyle(
              fontSize: 18,
            ),
            hintText: AppLocalizations.of(context)!.enterTagName,
            hintStyle: const TextStyle(
              fontSize: 18,
            ),
            prefixIcon: const Icon(PhosphorIconsLight.tag, size: 24),
            filled: true,
            fillColor: isDarkMode
                ? theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.7)
                : theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.3),
          ),
          style: const TextStyle(fontSize: 18),
          onChanged: (updatedTags) async {
            debugPrint(
                '[ManageTags][Section] ChipsInput.onChanged filePath=${widget.filePath} updatedTags=$updatedTags');
            setState(() {
              _selectedTags = List.from(updatedTags);
            });
            _updatePendingChanges();
          },
          onTextChanged: (value) {
            debugPrint(
                '[ManageTags][Section] ChipsInput.onTextChanged filePath=${widget.filePath} value="$value"');
            _draftTagText = value;
            _updateTagSuggestions(value);
          },
          onSubmitted: (value) {
            debugPrint(
                '[ManageTags][Section] ChipsInput.onSubmitted filePath=${widget.filePath} value="$value"');
            _commitDraftTag(value);
          },
          chipBuilder: (context, tag) {
            return TagInputChip(
              tag: tag,
              onDeleted: (removedTag) {
                setState(() {
                  _selectedTags.remove(removedTag);
                });
                _updatePendingChanges();
              },
              onSelected: (selectedTag) {},
            );
          },
        ),
        if (_tagSuggestions.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildTagSuggestionsSection(theme, isDarkMode),
        ],
        _buildPopularTagsSection(),
        _buildRecentTagsSection(),
      ],
    );
  }

  Widget _buildTagSuggestionsSection(ThemeData theme, bool isDarkMode) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 250),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2D2D2D) : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(PhosphorIconsLight.magnifyingGlass,
                    size: 18, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context)!.tagSuggestions,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _tagSuggestions = [];
                    });
                  },
                  child: const Icon(PhosphorIconsLight.x,
                      size: 20, color: Colors.white),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              itemCount: _tagSuggestions.length > 6 ? 6 : _tagSuggestions.length,
              itemBuilder: (context, index) {
                final suggestion = _tagSuggestions[index];
                return InkWell(
                  onTap: () {
                    _addSelectedTag(
                      suggestion,
                      clearSuggestions: true,
                      clearDraft: true,
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? const Color(0xFF2D2D2D)
                          : const Color(0xFFFFFFFF),
                      border: Border(
                        bottom: BorderSide(
                          color: theme.dividerColor,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        PhosphorIconsLight.tag,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      title: Text(
                        suggestion,
                        style: TextStyle(
                          fontSize: 16,
                          color:
                              isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPopularTagsSection() {
    if (!widget.showPopularTags) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: PopularTagsWidget(
        onTagSelected: (tag) {
          _addSelectedTag(tag);
        },
      ),
    );
  }

  Widget _buildRecentTagsSection() {
    if (!widget.showRecentTags) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: RecentTagsWidget(
        onTagSelected: (tag) {
          _addSelectedTag(tag);
        },
      ),
    );
  }
}

/// Widget to display a list of popular tags with animation and hover effects
class PopularTagsWidget extends StatelessWidget {
  final Function(String) onTagSelected;
  final int limit;

  const PopularTagsWidget({
    Key? key,
    required this.onTagSelected,
    this.limit = 20,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, int>>(
      future: TagManager.instance.getPopularTags(limit: limit),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final popularTags = snapshot.data ?? {};

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  PhosphorIconsLight.star,
                  size: 18,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.amber[300]
                      : Colors.amber,
                ),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context)!.popularTags,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedTagList(
              tags: popularTags.keys.toList(),
              counts: popularTags,
              onTagSelected: onTagSelected,
            ),
          ],
        );
      },
    );
  }
}

/// Widget to display a list of recently used tags with animation and hover effects
class RecentTagsWidget extends StatelessWidget {
  final Function(String) onTagSelected;
  final int limit;

  const RecentTagsWidget({
    Key? key,
    required this.onTagSelected,
    this.limit = 20,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: TagManager.getRecentTags(limit: limit),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final recentTags = snapshot.data ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  PhosphorIconsLight.clockCounterClockwise,
                  size: 18,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[400]
                      : Colors.grey[700],
                ),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context)!.recentTags,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedTagList(
              tags: recentTags,
              onTagSelected: onTagSelected,
            ),
          ],
        );
      },
    );
  }
}

/// An animated tag list that shows tags with hover effects and animations
class AnimatedTagList extends StatelessWidget {
  final List<String> tags;
  final Map<String, int>? counts;
  final Function(String) onTagSelected;

  const AnimatedTagList({
    Key? key,
    required this.tags,
    required this.onTagSelected,
    this.counts,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      children: tags.map((tag) {
        final count = counts != null ? counts![tag] : null;
        final displayText = count != null ? '$tag ($count)' : tag;

        return AnimatedTagChip(
          tag: tag,
          displayText: displayText,
          onTap: () => onTagSelected(tag),
        );
      }).toList(),
    );
  }
}

/// An animated tag chip with hover effects
class AnimatedTagChip extends StatefulWidget {
  final String tag;
  final String displayText;
  final VoidCallback onTap;

  const AnimatedTagChip({
    Key? key,
    required this.tag,
    required this.onTap,
    required this.displayText,
  }) : super(key: key);

  @override
  State<AnimatedTagChip> createState() => _AnimatedTagChipState();
}

class _AnimatedTagChipState extends State<AnimatedTagChip>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _elevationAnimation;
  late final TagColorManager _colorManager = TagColorManager.instance;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _elevationAnimation = Tween<double>(begin: 0, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Get tag color from TagColorManager
    final tagColor = _colorManager.getTagColor(widget.tag);

    // If tag has a custom color, use it; otherwise use theme colors
    // ignore: unnecessary_null_comparison
    final bool hasCustomColor = tagColor != null;

    // Dynamic colors based on hover state and tag color
    final Color backgroundColor = hasCustomColor
        ? (tagColor.withValues(alpha: _isHovered ? 0.3 : 0.2))
        : (_isHovered
            ? (isDark
                ? Colors.blue.withValues(alpha: 0.3)
                : theme.colorScheme.primary.withValues(alpha: 0.15))
            : (isDark ? Colors.grey[700]! : Colors.grey[200]!));
    final Color effectiveBackground =
        Color.alphaBlend(backgroundColor, theme.colorScheme.surface);
    final Color foregroundColor = _bestForegroundColor(effectiveBackground);
    final Color textColor = foregroundColor;
    final Color iconColor = foregroundColor.withValues(alpha: 0.92);

    final Color borderColor = hasCustomColor
        ? (tagColor.withValues(alpha: _isHovered ? 0.8 : 0.3))
        : (_isHovered
            ? theme.colorScheme.primary.withValues(alpha: 0.5)
            : Colors.transparent);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _isHovered = true);
        _controller.forward();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _controller.reverse();
      },
      child: GestureDetector(
        onTap: () {
          _controller.forward().then((_) => _controller.reverse());
          widget.onTap();
        },
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Material(
                elevation: _elevationAnimation.value,
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: borderColor,
                      width: 1,
                    ),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        PhosphorIconsLight.tag,
                        size: 14,
                        color: iconColor,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          widget.displayText,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 13,
                            fontWeight: _isHovered
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (_isHovered) ...[
                        const SizedBox(width: 4),
                        Icon(
                          PhosphorIconsLight.plusCircle,
                          size: 14,
                          color: iconColor,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Color _bestForegroundColor(Color background) {
    const light = Colors.white;
    const dark = Colors.black;
    final lightContrast = _contrastRatio(background, light);
    final darkContrast = _contrastRatio(background, dark);
    return lightContrast >= darkContrast ? light : dark;
  }

  double _contrastRatio(Color a, Color b) {
    final aLuminance = a.computeLuminance();
    final bLuminance = b.computeLuminance();
    final lighter = aLuminance > bLuminance ? aLuminance : bLuminance;
    final darker = aLuminance > bLuminance ? bLuminance : aLuminance;
    return (lighter + 0.05) / (darker + 0.05);
  }
}
