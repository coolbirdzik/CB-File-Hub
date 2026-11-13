import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../design_system/cb_design_system.dart';
import '../../components/common/optimized_interaction_handler.dart';
import '../../utils/item_interaction_style.dart';
import '../../widgets/compact_list_content.dart';

/// A workspace section shown among the hosts the way the file browser shows
/// a folder among files: click selects on desktop, double click or Enter
/// opens it, a tap opens it on mobile.
class SshFolderItem extends StatefulWidget {
  const SshFolderItem({
    super.key,
    required this.icon,
    required this.name,
    required this.detail,
    required this.isGrid,
    required this.isDesktop,
    required this.isSelected,
    required this.onSelect,
    required this.onOpen,
  });

  final IconData icon;
  final String name, detail;
  final bool isGrid, isDesktop, isSelected;
  final VoidCallback onSelect, onOpen;

  @override
  State<SshFolderItem> createState() => _SshFolderItemState();
}

class _SshFolderItemState extends State<SshFolderItem> {
  final _focus = FocusNode();
  bool _hovering = false;
  bool _showFocus = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _select() {
    _focus.requestFocus();
    widget.onSelect();
  }

  @override
  Widget build(BuildContext context) => FocusableActionDetector(
    focusNode: _focus,
    onShowHoverHighlight: (value) => setState(() => _hovering = value),
    onShowFocusHighlight: (value) => setState(() => _showFocus = value),
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    },
    actions: {
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          widget.onOpen();
          return null;
        },
      ),
    },
    child: Semantics(
      selected: widget.isSelected,
      button: true,
      label: widget.name,
      onTap: widget.onOpen,
      child: OptimizedInteractionLayer(
        onTap: widget.isDesktop ? _select : widget.onOpen,
        onDoubleTap: widget.isDesktop ? widget.onOpen : null,
        child: widget.isGrid
            ? LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth < 200
                    ? CbSurface(
                        selected: widget.isSelected,
                        clip: true,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _tile(24),
                              const SizedBox(height: 4),
                              Text(
                                widget.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: CbTypography.bodySm,
                              ),
                            ],
                          ),
                        ),
                      )
                    : _grid(context),
              )
            : _list(context),
      ),
    ),
  );

  Widget _tile(double size) {
    final colors = context.cbColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.accent.tint,
        borderRadius: CbRadii.smAll,
      ),
      child: SizedBox.square(
        dimension: size,
        child: Icon(widget.icon, size: size / 2, color: colors.accent.text),
      ),
    );
  }

  Widget _list(BuildContext context) {
    final colors = context.cbColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ItemInteractionStyle.backgroundColor(
          theme: Theme.of(context),
          isDesktopMode: widget.isDesktop,
          isSelected: widget.isSelected,
          isHovering: _hovering,
        ),
        border: _showFocus
            ? Border.all(color: colors.focusRing, width: CbStrokes.emphasis)
            : null,
      ),
      child: CompactListContent(
        leading: _tile(CbSizes.controlXs),
        label: Text(
          widget.name,
          style: CbTypography.body.copyWith(color: colors.textPrimary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          widget.detail,
          style: CbTypography.bodySm.copyWith(color: colors.textTertiary),
        ),
      ),
    );
  }

  Widget _grid(BuildContext context) {
    final colors = context.cbColors;
    return CbSurface(
      selected: widget.isSelected,
      clip: true,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CbSpacing.md - 2),
            child: Row(
              children: [
                _tile(CbSizes.controlMd),
                const SizedBox(width: CbSpacing.md - 2),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name,
                        style: CbTypography.headingSm.copyWith(
                          color: colors.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        widget.detail,
                        style: CbTypography.labelXs.copyWith(
                          color: colors.textTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  PhosphorIconsLight.caretRight,
                  size: CbSizes.iconSm,
                  color: colors.textTertiary,
                ),
              ],
            ),
          ),
          if (_showFocus)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: CbRadii.mdAll,
                    border: Border.all(
                      color: colors.focusRing,
                      width: CbStrokes.emphasis,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
