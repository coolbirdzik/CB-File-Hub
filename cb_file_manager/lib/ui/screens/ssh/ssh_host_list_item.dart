import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../design_system/cb_design_system.dart';
import '../../components/common/optimized_interaction_handler.dart';
import '../../utils/item_interaction_style.dart';
import '../../widgets/compact_list_content.dart';

class SshHostListItem extends StatefulWidget {
  const SshHostListItem({
    super.key,
    required this.name,
    required this.description,
    required this.isDesktop,
    required this.isSelected,
    required this.onSelect,
    required this.onOpen,
    this.onOpenInNewTab,
    required this.onBrowse,
    this.onBrowseInNewTab,
    this.showTerminalAction = true,
    required this.menuBuilder,
    required this.menuTooltip,
    required this.terminalTooltip,
    required this.browseTooltip,
    this.isConnecting = false,
    this.isGrid = false,
    this.authenticationLabel,
  });

  final String name, description, menuTooltip, terminalTooltip, browseTooltip;
  final bool isDesktop, isSelected, isConnecting, isGrid;
  final String? authenticationLabel;
  final VoidCallback onSelect;
  final VoidCallback? onOpen, onOpenInNewTab, onBrowse, onBrowseInNewTab;
  final bool showTerminalAction;
  final PopupMenuItemBuilder<void> menuBuilder;

  @override
  State<SshHostListItem> createState() => _SshHostListItemState();
}

class _SshHostListItemState extends State<SshHostListItem> {
  final _focus = FocusNode();
  final _menu = GlobalKey<PopupMenuButtonState<void>>();
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
          widget.onOpen?.call();
          return null;
        },
      ),
    },
    child: Semantics(
      selected: widget.isSelected,
      button: true,
      label: widget.name,
      onTap: widget.onOpen,
      child: Tooltip(
        message: widget.description,
        child: widget.isGrid ? _grid(context) : _list(context),
      ),
    ),
  );

  Widget _list(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: ItemInteractionStyle.backgroundColor(
        theme: Theme.of(context),
        isDesktopMode: widget.isDesktop,
        isSelected: widget.isSelected,
        isHovering: _hovering,
      ),
      border: _showFocus
          ? Border.all(
              color: context.cbColors.focusRing,
              width: CbStrokes.emphasis,
            )
          : null,
    ),
    child: Row(
      children: [
        Expanded(
          child: _interact(
            CompactListContent(
              leading: _terminalIcon(context, CbSizes.iconLg),
              label: Text(
                widget.name,
                style: CbTypography.body.copyWith(
                  color: context.cbColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        _menuButton(compact: true),
      ],
    ),
  );

  Widget _grid(BuildContext context) {
    final colors = context.cbColors;
    return CbSurface(
      selected: widget.isSelected,
      clip: true,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _interact(
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      CbSpacing.md,
                      CbSpacing.md,
                      CbSpacing.xxl,
                      CbSpacing.sm,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: CbSizes.controlLg,
                          height: CbSizes.controlLg,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.accent.tint,
                              borderRadius: CbRadii.smAll,
                            ),
                            child: Center(
                              child: _terminalIcon(context, CbSizes.iconLg),
                            ),
                          ),
                        ),
                        const SizedBox(width: CbSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.name,
                                style: CbTypography.headingSm.copyWith(
                                  color: colors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: CbSpacing.xxs),
                              Text(
                                widget.description,
                                style: CbTypography.monoSm.copyWith(
                                  color: colors.textSecondary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (widget.authenticationLabel != null) ...[
                                const SizedBox(height: CbSpacing.xs),
                                Text(
                                  widget.authenticationLabel!,
                                  style: CbTypography.caption.copyWith(
                                    color: colors.textTertiary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Action strip: one more fill step instead of a rule above it.
              DecoratedBox(
                decoration: BoxDecoration(color: colors.fillSubtle),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CbSpacing.sm,
                    vertical: CbSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      if (widget.showTerminalAction) ...[
                        _openInNewTabOnMiddleClick(
                          onMiddleClick: widget.onOpenInNewTab,
                          child: CbButton.icon(
                            icon: PhosphorIconsLight.terminalWindow,
                            tooltip: widget.terminalTooltip,
                            size: CbButtonSize.sm,
                            onPressed: widget.onOpen,
                          ),
                        ),
                        const SizedBox(width: CbSpacing.xs),
                      ],
                      _openInNewTabOnMiddleClick(
                        onMiddleClick: widget.onBrowseInNewTab,
                        child: CbButton.icon(
                          icon: PhosphorIconsLight.folderOpen,
                          tooltip: widget.browseTooltip,
                          size: CbButtonSize.sm,
                          onPressed: widget.onBrowse,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: CbSpacing.xs,
            right: CbSpacing.xs,
            child: _menuButton(),
          ),
          // Selection is carried by the surface fill; only keyboard focus
          // draws a ring, because it is state rather than decoration.
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

  Widget _terminalIcon(BuildContext context, double size) => widget.isConnecting
      ? SizedBox(
          width: size,
          height: size,
          child: const CircularProgressIndicator(strokeWidth: 2),
        )
      : Icon(
          PhosphorIconsLight.terminalWindow,
          size: size,
          color: context.cbColors.accent.text,
        );

  Widget _interact(Widget child) => _openInNewTabOnMiddleClick(
    onMiddleClick: widget.onOpenInNewTab,
    child: OptimizedInteractionLayer(
      onTap: widget.isDesktop ? _select : () => widget.onOpen?.call(),
      onDoubleTap: widget.isDesktop ? widget.onOpen : null,
      onSecondaryTapUp: (_) {
        _select();
        _menu.currentState?.showButtonMenu();
      },
      child: child,
    ),
  );

  Widget _openInNewTabOnMiddleClick({
    required Widget child,
    required VoidCallback? onMiddleClick,
  }) => Listener(
    onPointerDown: onMiddleClick == null
        ? null
        : (event) {
            if (event.buttons == kMiddleMouseButton) onMiddleClick();
          },
    child: child,
  );

  Widget _menuButton({bool compact = false}) => SizedBox(
    width: compact ? CbSizes.controlMd : CbSizes.controlSm,
    height: compact ? CbSizes.controlMd : CbSizes.controlSm,
    child: PopupMenuButton<void>(
      key: _menu,
      tooltip: widget.menuTooltip,
      padding: EdgeInsets.zero,
      iconSize: CbSizes.iconSm,
      popUpAnimationStyle: AnimationStyle.noAnimation,
      enableFeedback: false,
      style: const ButtonStyle(
        overlayColor: WidgetStatePropertyAll(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
        animationDuration: Duration.zero,
      ),
      icon: const Icon(PhosphorIconsLight.dotsThree),
      itemBuilder: widget.menuBuilder,
    ),
  );
}
