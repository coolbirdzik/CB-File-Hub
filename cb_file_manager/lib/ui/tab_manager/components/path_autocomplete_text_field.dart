import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:path/path.dart' as p;

enum PathSuggestionType { recent, filesystem }

class PathSuggestion {
  final String value;
  final PathSuggestionType type;

  const PathSuggestion({
    required this.value,
    required this.type,
  });
}

class PathAutocompleteTextField extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final InputDecoration decoration;
  final TextInputAction textInputAction;
  final int maxSuggestions;
  final bool submitOnSuggestionTap;
  final Future<List<String>> Function()? recentPathsLoader;

  const PathAutocompleteTextField({
    Key? key,
    required this.controller,
    required this.onSubmitted,
    required this.decoration,
    this.textInputAction = TextInputAction.go,
    this.maxSuggestions = 12,
    this.submitOnSuggestionTap = false,
    this.recentPathsLoader,
  }) : super(key: key);

  @override
  State<PathAutocompleteTextField> createState() =>
      _PathAutocompleteTextFieldState();
}

class _PathAutocompleteTextFieldState extends State<PathAutocompleteTextField> {
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();

  OverlayEntry? _overlayEntry;
  Timer? _debounce;
  int _computeToken = 0;

  List<String> _recentPaths = <String>[];
  List<PathSuggestion> _suggestions = <PathSuggestion>[];
  int _selectedIndex = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _removeOverlay();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadRecentPaths() async {
    final loader = widget.recentPathsLoader ??
        () => UserPreferences.instance.getRecentPaths(limit: 50);
    try {
      final paths = await loader();
      if (!mounted) return;
      setState(() {
        _recentPaths = paths;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _recentPaths = <String>[];
      });
    }
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      unawaited(
          _loadRecentPaths().then((_) => _updateSuggestions(force: true)));
      _updateSuggestions(force: true);
      return;
    }
    _removeOverlay();
  }

  void _onTextChanged() {
    if (!_focusNode.hasFocus) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || !_focusNode.hasFocus) return;
      _updateSuggestions();
    });
  }

  bool _pathsEqualForSearch(String a, String b) {
    if (Platform.isWindows) {
      return a.toLowerCase() == b.toLowerCase();
    }
    return a == b;
  }

  bool _matchesQuery(String candidate, String query) {
    if (query.isEmpty) return true;
    if (Platform.isWindows) {
      final c = candidate.toLowerCase();
      final q = query.toLowerCase();
      return c.startsWith(q) || c.contains(q);
    }
    return candidate.startsWith(query) || candidate.contains(query);
  }

  bool _shouldSuggestFromFileSystem(String query) {
    if (query.trim().isEmpty) return false;
    if (query.startsWith('#')) return false;
    if (Platform.isWindows) {
      return query.contains('\\') ||
          query.contains('/') ||
          RegExp(r'^[a-zA-Z]:').hasMatch(query);
    }
    return query.contains(Platform.pathSeparator) || query.startsWith('/');
  }

  List<String> _filesystemSuggestions(String query) {
    if (!_shouldSuggestFromFileSystem(query)) return <String>[];

    final sep = Platform.pathSeparator;
    final normalized = Platform.isWindows ? query.replaceAll('/', '\\') : query;

    String parent;
    String prefix;
    if (normalized.endsWith(sep)) {
      parent = normalized;
      prefix = '';
    } else {
      parent = p.dirname(normalized);
      prefix = p.basename(normalized);
    }

    if (parent.isEmpty || parent == '.') return <String>[];

    try {
      final dir = Directory(parent);
      if (!dir.existsSync()) return <String>[];

      final prefixLower = Platform.isWindows ? prefix.toLowerCase() : prefix;
      final entries = dir
          .listSync(followLinks: false)
          .whereType<Directory>()
          .map((d) => d.path)
          .toList(growable: false);

      final List<String> matches = <String>[];
      for (final candidate in entries) {
        final name = p.basename(candidate);
        final comparable = Platform.isWindows ? name.toLowerCase() : name;
        if (prefixLower.isEmpty || comparable.startsWith(prefixLower)) {
          matches.add(candidate);
          if (matches.length >= widget.maxSuggestions) break;
        }
      }
      return matches;
    } catch (_) {
      return <String>[];
    }
  }

  Future<void> _updateSuggestions({bool force = false}) async {
    if (!mounted) return;
    final query = widget.controller.text.trim();

    final int token = ++_computeToken;

    final List<PathSuggestion> next = <PathSuggestion>[];

    if (query.isEmpty) {
      for (final p in _recentPaths) {
        next.add(PathSuggestion(value: p, type: PathSuggestionType.recent));
        if (next.length >= widget.maxSuggestions) break;
      }
    } else {
      final fs =
          await Future<List<String>>(() => _filesystemSuggestions(query));
      if (!mounted || token != _computeToken) return;

      for (final v in fs) {
        next.add(PathSuggestion(value: v, type: PathSuggestionType.filesystem));
      }

      for (final r in _recentPaths) {
        if (!_matchesQuery(r, query)) continue;
        if (next.any((s) => _pathsEqualForSearch(s.value, r))) continue;
        next.add(PathSuggestion(value: r, type: PathSuggestionType.recent));
        if (next.length >= widget.maxSuggestions) break;
      }
    }

    if (!mounted || token != _computeToken) return;

    final changed = force ||
        next.length != _suggestions.length ||
        !_listsEqual(next, _suggestions);

    if (!changed) return;

    setState(() {
      _suggestions = next;
      _selectedIndex = _suggestions.isEmpty ? -1 : 0;
    });

    if (!_focusNode.hasFocus || _suggestions.isEmpty) {
      _removeOverlay();
      return;
    }

    _showOrUpdateOverlay();
  }

  bool _listsEqual(List<PathSuggestion> a, List<PathSuggestion> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].type != b[i].type) return false;
      if (!_pathsEqualForSearch(a[i].value, b[i].value)) return false;
    }
    return true;
  }

  void _showOrUpdateOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }

    _overlayEntry = OverlayEntry(
      builder: (context) {
        final renderBox =
            _fieldKey.currentContext?.findRenderObject() as RenderBox?;
        final size = renderBox?.size ?? Size.zero;

        final theme = Theme.of(context);

        return Positioned(
          width: size.width,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(0, size.height + 6),
            child: Material(
              elevation: 0,
              borderRadius: BorderRadius.circular(16.0),
              color: theme.colorScheme.surface,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    shrinkWrap: true,
                    itemCount: _suggestions.length,
                    itemBuilder: (context, index) {
                      final s = _suggestions[index];
                      final bool selected = index == _selectedIndex;

                      final icon = s.type == PathSuggestionType.filesystem
                          ? PhosphorIconsLight.folder
                          : PhosphorIconsLight.clockCounterClockwise;

                      return Material(
                        color: selected
                            ? theme.colorScheme.primary.withValues(alpha: 0.12)
                            : Colors.transparent,
                        child: InkWell(
                          onTap: () => _applySuggestion(index),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  icon,
                                  size: 18,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    s.value,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _applySuggestion(int index) {
    if (index < 0 || index >= _suggestions.length) return;
    final value = _suggestions[index].value;
    widget.controller.text = value;
    widget.controller.selection = TextSelection.collapsed(offset: value.length);
    _removeOverlay();
    if (widget.submitOnSuggestionTap) {
      _focusNode.unfocus();
      widget.onSubmitted(value);
    } else {
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        key: _fieldKey,
        controller: widget.controller,
        focusNode: _focusNode,
        decoration: widget.decoration,
        onSubmitted: (value) {
          _removeOverlay();
          widget.onSubmitted(value);
        },
        textInputAction: widget.textInputAction,
        onTap: () {
          if (!_focusNode.hasFocus) return;
          _updateSuggestions(force: true);
        },
        onTapOutside: (_) => _removeOverlay(),
      ),
    );
  }
}
