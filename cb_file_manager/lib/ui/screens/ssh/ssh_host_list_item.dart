import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../design_system/cb_design_system.dart';
import '../../components/common/optimized_interaction_handler.dart';
import '../../utils/item_interaction_style.dart';
import '../../widgets/compact_list_content.dart';
import 'ssh_connection_status.dart';
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
    this.isDetails = false,
    this.authenticationLabel,
    this.usesKeyAuth = false,
    this.group = '',
    this.routeLabel,
    this.viaProxy = false,
    this.connectionStatus,
  });

  /// Unscaled height of a grid card: a name of up to two lines level with the
  /// actions, then the address and the connection line.
  static const double gridExtent = 90;

  /// [description] is the `user@host:port` address.
  final String name, description, menuTooltip, terminalTooltip, browseTooltip;
  final String group;
  final bool isDesktop, isSelected, isConnecting, isGrid, usesKeyAuth;
  final String? authenticationLabel;

  /// How the host is reached at rest: through which proxy, or directly.
  final String? routeLabel;
  final bool viaProxy;

  /// The proxy and SSH steps while connecting or after a failure; replaces
  /// [routeLabel]. Idle or null shows the route.
  final SshConnectionStatus? connectionStatus;
  final VoidCallback onSelect;
  final VoidCallback? onOpen, onOpenInNewTab, onBrowse, onBrowseInNewTab;
  final bool showTerminalAction;
  final bool isDetails;
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
          ?widget.routeLabel,
        ].join('\n'),
        child: widget.isGrid
            ? LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth < 240
                    ? _compactGrid(context)
                    : _grid(context),
              )
            : _list(context),
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
                // The address only joins the row once the name keeps room; a
                // connection status always does.
                trailing: _connecting
                    ? ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth * 0.45,
                        ),
                        child: _steps(),
                      )
                    : !widget.isDetails && constraints.maxWidth < 480
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

  Widget _compactGrid(BuildContext context) => CbSurface(
    selected: widget.isSelected,
    clip: true,
    child: Stack(
      children: [
        Positioned.fill(
          child: _interact(
            Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _avatar(24),
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
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: _menuButton(compact: true, extent: 18),
        ),
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
    // The name stops short of the actions; the lines below run beneath them.
    final actionsWidth =
        actionCount * CbSizes.controlSm +
        (actionCount - 1) * buttonGap +
        CbSpacing.sm;
    // Two name lines always keep their room, so a name that rewraps when the
    // actions appear never moves the lines below it.
    final nameHeight = MediaQuery.textScalerOf(context).scale(20) * 2;
    const topInset = CbSpacing.sm;
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
                  topInset,
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
                            height: nameHeight,
                            child: Padding(
                              padding: EdgeInsets.only(right: actionsWidth),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  widget.name,
                                  style: CbTypography.headingSm.copyWith(
                                    color: colors.textPrimary,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
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
                          const SizedBox(height: 2),
                          _connectionRow(context),
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
            top: topInset + (nameHeight - CbSizes.controlSm) / 2,
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

  bool get _connecting => !(widget.connectionStatus?.isIdle ?? true);

  Widget _steps() => SshConnectionSteps(
    status: widget.connectionStatus!,
    proxy: null,
    viaProxy: widget.viaProxy,
    address: widget.description,
    dense: true,
  );

  /// The proxy and SSH steps while connecting or after a failure, otherwise
  /// the route, followed by the group.
  Widget _connectionRow(BuildContext context) {
    final colors = context.cbColors;
    final route = widget.routeLabel;
    return Row(
      children: [
        if (_connecting)
          Expanded(child: _steps())
        else if (route != null) ...[
          Icon(
            widget.viaProxy
                ? PhosphorIconsLight.shuffleAngular
                : PhosphorIconsLight.plugsConnected,
            size: CbSizes.iconXs,
            color: colors.textTertiary,
          ),
          const SizedBox(width: CbSpacing.xs),
          Expanded(
            child: Text(
              route,
              style: CbTypography.labelXs.copyWith(color: colors.textTertiary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ] else
          const Spacer(),
        if (widget.group.isNotEmpty) ...[
          const SizedBox(width: CbSpacing.xs + 2),
          // Capped so the status keeps priority.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 96),
            child: _groupBadge(context),
          ),
        ],
      ],
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
        _focus.requestFocus();
        if (!widget.isSelected) widget.onSelect();
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

  Widget _menuButton({bool compact = false, double? extent}) => SizedBox(
    width: extent ?? (compact ? CbSizes.controlMd : CbSizes.controlSm),
    height: extent ?? (compact ? CbSizes.controlMd : CbSizes.controlSm),
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
