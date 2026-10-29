import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../design_system/cb_design_system.dart';
import '../../components/common/optimized_interaction_handler.dart';
import '../../utils/item_interaction_style.dart';
import '../../widgets/compact_list_content.dart';
import 'ssh_host_avatar.dart';

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
    this.usesKeyAuth = false,
    this.group = '',
  });

  /// Unscaled height of a grid card: a name line level with the actions and a
  /// full-width address line.
  static const double gridExtent = 60;

  /// [description] is the `user@host:port` address.
  final String name, description, menuTooltip, terminalTooltip, browseTooltip;
  final String group;
  final bool isDesktop, isSelected, isConnecting, isGrid, usesKeyAuth;
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
        message: [
          widget.description,
          if (widget.group.isNotEmpty) widget.group,
          ?widget.authenticationLabel,
        ].join('\n'),
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
          child: LayoutBuilder(
            builder: (context, constraints) => _interact(
              CompactListContent(
                leading: _avatar(CbSizes.controlXs),
                label: Text(
                  widget.name,
                  style: CbTypography.body.copyWith(
                    color: context.cbColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // The address only joins the row once the name keeps room.
                trailing: constraints.maxWidth < 480
                    ? null
                    : ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth * 0.45,
                        ),
                        child: Text(
                          widget.description,
                          style: CbTypography.monoSm.copyWith(
                            color: context.cbColors.textTertiary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
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
    const buttonGap = CbSpacing.xxs;
    // On desktop the quick actions appear with hover or keyboard focus, so a
    // resting card gives its width to the name. Not with selection: on a
    // touchscreen the second tap of a double-tap would land on a button that
    // the first tap revealed. Mobile has no hover, so the actions stay.
    final showQuickActions =
        !widget.isDesktop || _hovering || _showFocus || widget.isConnecting;
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showQuickActions && widget.showTerminalAction) ...[
          _openInNewTabOnMiddleClick(
            onMiddleClick: widget.onOpenInNewTab,
            child: CbButton.icon(
              icon: PhosphorIconsLight.terminalWindow,
              tooltip: widget.terminalTooltip,
              size: CbButtonSize.sm,
              onPressed: widget.onOpen,
            ),
          ),
          const SizedBox(width: buttonGap),
        ],
        if (showQuickActions) ...[
          _openInNewTabOnMiddleClick(
            onMiddleClick: widget.onBrowseInNewTab,
            child: CbButton.icon(
              icon: PhosphorIconsLight.folderOpen,
              tooltip: widget.browseTooltip,
              size: CbButtonSize.sm,
              onPressed: widget.onBrowse,
            ),
          ),
          const SizedBox(width: buttonGap),
        ],
        _menuButton(),
      ],
    );
    final actionCount = !showQuickActions
        ? 1
        : widget.showTerminalAction
        ? 3
        : 2;
    // The name line stops short of the actions; the address runs beneath them.
    final actionsWidth =
        actionCount * CbSizes.controlSm +
        (actionCount - 1) * buttonGap +
        CbSpacing.sm;
    return CbSurface(
      selected: widget.isSelected,
      clip: true,
      child: Stack(
        children: [
          Positioned.fill(
            child: _interact(
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CbSpacing.md - 2,
                  CbSpacing.sm,
                  CbSpacing.md - 2,
                  CbSpacing.sm,
                ),
                child: Row(
                  children: [
                    _avatar(CbSizes.controlMd),
                    const SizedBox(width: CbSpacing.md - 2),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: CbSizes.controlSm,
                            child: Padding(
                              padding: EdgeInsets.only(right: actionsWidth),
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      widget.name,
                                      style: CbTypography.headingSm.copyWith(
                                        color: colors.textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (widget.group.isNotEmpty) ...[
                                    const SizedBox(width: CbSpacing.xs + 2),
                                    // Capped so the name keeps priority.
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 72,
                                      ),
                                      child: _groupBadge(context),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              Icon(
                                widget.usesKeyAuth
                                    ? PhosphorIconsLight.key
                                    : PhosphorIconsLight.password,
                                size: CbSizes.iconXs,
                                color: colors.textTertiary,
                              ),
                              const SizedBox(width: CbSpacing.xs),
                              Expanded(
                                child: Text(
                                  widget.description,
                                  style: CbTypography.monoSm.copyWith(
                                    color: colors.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Outside the interaction layer, so a button press neither selects
          // nor opens the card.
          Positioned(
            top: CbSpacing.sm,
            right: CbSpacing.xs + 2,
            child: actions,
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

  Widget _groupBadge(BuildContext context) {
    final colors = context.cbColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: CbRadii.all(CbRadii.xs),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CbSpacing.xs + 2,
          vertical: 1,
        ),
        child: Text(
          widget.group,
          style: CbTypography.labelXs.copyWith(color: colors.textSecondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _avatar(double size) => SshHostAvatar(
    name: widget.name,
    detail: widget.description,
    group: widget.group,
    size: size,
    loading: widget.isConnecting,
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
