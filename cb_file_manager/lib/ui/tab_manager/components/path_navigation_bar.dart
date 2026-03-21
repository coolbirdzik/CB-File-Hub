import 'dart:io';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'address_bar_menu.dart';

class PathNavigationBar extends StatefulWidget {
  final String currentPath;
  final String tabId;
  final bool isNetworkPath;
  final TextEditingController pathController;
  final Function(String) onPathSubmitted;
  final List<AddressBarMenuItem>? menuItems;

  const PathNavigationBar({
    Key? key,
    required this.currentPath,
    required this.tabId,
    required this.isNetworkPath,
    required this.pathController,
    required this.onPathSubmitted,
    this.menuItems,
  }) : super(key: key);

  @override
  // ignore: library_private_types_in_public_api
  State<PathNavigationBar> createState() => _PathNavigationBarState();
}

class _PathNavigationBarState extends State<PathNavigationBar> {
  bool _isEditing = false;
  late FocusNode _pathFocusNode;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _pathFocusNode = FocusNode();
    if (widget.isNetworkPath) {
      _isEditing = true;
    }
  }

  @override
  void dispose() {
    _pathFocusNode.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _pathFocusNode.requestFocus();
    });
  }

  void _stopEditing() {
    if (widget.isNetworkPath) {
      return;
    }
    setState(() {
      _isEditing = false;
      _pathFocusNode.unfocus();
    });
  }

  Widget _buildPathSegments() {
    final pathSegments = widget.currentPath.split(Platform.pathSeparator);
    if (pathSegments.isEmpty ||
        (pathSegments.length == 1 && pathSegments[0].isEmpty)) {
      return GestureDetector(
        onTap: _startEditing,
        child: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: const Text(
            'This PC',
            style: TextStyle(fontSize: 16.0),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: _startEditing,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: _isHovering
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16.0),
          ),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            shrinkWrap: true,
            itemCount: pathSegments.length,
            separatorBuilder: (context, index) =>
                const Icon(PhosphorIconsLight.caretRight, size: 18.0),
            itemBuilder: (context, index) {
              final segment = pathSegments[index];
              if (index == 0 && segment.isEmpty) {
                return const SizedBox.shrink();
              }
              final segmentPath = pathSegments
                  .sublist(0, index + 1)
                  .join(Platform.pathSeparator);
              return InkWell(
                onTap: () => widget.onPathSubmitted(segmentPath),
                borderRadius: BorderRadius.circular(16.0),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8.0, vertical: 4.0),
                  child: Text(
                    segment.isEmpty && index == 0 ? 'Root' : segment,
                    style: const TextStyle(fontSize: 16.0),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEditablePathField() {
    return Container(
      height: 40.0,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: TextField(
        controller: widget.pathController,
        focusNode: _pathFocusNode,
        onSubmitted: (path) {
          widget.onPathSubmitted(path);
          _stopEditing();
        },
        decoration: InputDecoration(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          border: InputBorder.none,
          hintText: 'Enter path...',
          hintStyle: TextStyle(
            color: Theme.of(context)
                .textTheme
                .bodySmall
                ?.color
                ?.withValues(alpha: 0.6),
          ),
        ),
        style: TextStyle(
          fontSize: 14.0,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
        onTapOutside: (_) => _stopEditing(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _isEditing ? _buildEditablePathField() : _buildPathSegments(),
        ),
        if (widget.menuItems != null && widget.menuItems!.isNotEmpty)
          AddressBarMenu(
            items: widget.menuItems!,
            tooltip: 'Tùy chọn',
          ),
      ],
    );
  }
}
