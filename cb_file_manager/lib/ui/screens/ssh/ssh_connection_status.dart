import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../config/translation_helper.dart';
import '../../../design_system/cb_design_system.dart';
import '../../../services/ssh/ssh_profile_store.dart';

enum SshStepState { idle, active, done, failed }

/// Where an SSH connection attempt stands, split into the proxy step and the
/// SSH step. [phase] is the last step reached; with [failed] it is the step
/// that failed.
@immutable
class SshConnectionStatus {
  const SshConnectionStatus({this.phase, this.failed = false});

  final SshConnectPhase? phase;
  final bool failed;

  bool get isIdle => phase == null && !failed;

  SshStepState get proxy {
    final phase = this.phase;
    if (phase == null) return SshStepState.idle;
    if (!phase.isProxy) return SshStepState.done;
    return failed ? SshStepState.failed : SshStepState.active;
  }

  /// A failure before any step (a missing key, say) belongs to SSH.
  SshStepState get ssh {
    final phase = this.phase;
    if (phase?.isProxy ?? !failed) return SshStepState.idle;
    if (failed) return SshStepState.failed;
    return phase == SshConnectPhase.connected
        ? SshStepState.done
        : SshStepState.active;
  }

  String proxyLabel(AppLocalizations tr) => switch (proxy) {
    SshStepState.idle => tr.sshStatusNotConnected,
    SshStepState.active =>
      phase == SshConnectPhase.proxyNegotiating
          ? tr.sshStatusTunneling
          : tr.sshConnecting,
    SshStepState.done => tr.connected,
    SshStepState.failed => tr.sshStatusFailed,
  };

  String sshLabel(AppLocalizations tr) => switch (ssh) {
    SshStepState.idle => tr.sshStatusNotConnected,
    SshStepState.active => switch (phase) {
      SshConnectPhase.verifyingHostKey => tr.sshStatusVerifyingHost,
      SshConnectPhase.authenticating => tr.sshStatusAuthenticating,
      _ => tr.sshConnecting,
    },
    SshStepState.done => tr.connected,
    SshStepState.failed =>
      phase == SshConnectPhase.authenticating
          ? tr.sshStatusAuthFailed
          : tr.sshStatusFailed,
  };
}

Color sshStepColor(BuildContext context, SshStepState state) {
  final colors = context.cbColors;
  return switch (state) {
    SshStepState.idle => colors.textTertiary,
    SshStepState.active => colors.accent.base,
    SshStepState.done => colors.status.success,
    SshStepState.failed => colors.status.danger,
  };
}

/// Proxy name, protocol and address, never its credentials.
String sshProxyDescription(SshProxy proxy) =>
    '${proxy.name} · ${proxy.protocol} ${proxy.host}:${proxy.port}';

/// The proxy and SSH steps of a connection as one compact run, for a
/// toolbar or a host card. Only the step in progress or failed has a label;
/// the icons say done or not started, and the tooltip spells out both steps
/// with their addresses.
class SshConnectionSteps extends StatelessWidget {
  const SshConnectionSteps({
    super.key,
    required this.status,
    required this.proxy,
    required this.address,
    this.viaProxy,
    this.dense = false,
  });

  final SshConnectionStatus status;

  /// Null for a direct connection.
  final SshProxy? proxy;

  /// Whether a proxy is used even when [proxy] is unknown; defaults to
  /// `proxy != null`.
  final bool? viaProxy;

  /// The `user@host:port` address.
  final String address;

  /// Smaller text, for a host card.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final colors = context.cbColors;
    final proxy = this.proxy;
    final viaProxy = this.viaProxy ?? proxy != null;
    final proxyFocused =
        viaProxy &&
        (status.proxy == SshStepState.active ||
            status.proxy == SshStepState.failed);
    final caretGap = dense ? CbSpacing.xs : CbSpacing.xs + 2;
    final caretSize = dense ? CbSizes.iconXs : CbSizes.iconSm;
    return Tooltip(
      message: [
        viaProxy
            ? '${tr.sshProxy}: ${status.proxyLabel(tr)}'
                  '${proxy == null ? '' : ' · ${sshProxyDescription(proxy)}'}'
            : '${tr.sshProxy}: ${tr.sshProxyNone}',
        'SSH: ${status.sshLabel(tr)} · $address',
      ].join('\n'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The step in progress or failed takes what the other leaves; the
          // other needs only its icon and title.
          final half =
              math.max(0.0, constraints.maxWidth - caretSize - caretGap * 2) /
              2;
          Widget fit(Widget step, {required bool focused}) => focused
              ? Flexible(child: step)
              : ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: half),
                  child: step,
                );
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (viaProxy) ...[
                fit(
                  _step(
                    context,
                    key: const ValueKey('ssh-step-proxy'),
                    title: tr.sshProxy,
                    state: status.proxy,
                    label: status.proxyLabel(tr),
                  ),
                  focused: proxyFocused,
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: caretGap),
                  child: Icon(
                    PhosphorIconsLight.caretRight,
                    size: caretSize,
                    color: colors.textTertiary,
                  ),
                ),
              ],
              fit(
                _step(
                  context,
                  key: const ValueKey('ssh-step-ssh'),
                  title: 'SSH',
                  state: status.ssh,
                  label: status.sshLabel(tr),
                ),
                focused: !proxyFocused,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _step(
    BuildContext context, {
    required Key key,
    required String title,
    required SshStepState state,
    required String label,
  }) {
    final colors = context.cbColors;
    final color = sshStepColor(context, state);
    final iconSize = dense ? CbSizes.iconXs : CbSizes.iconSm;
    final textStyle = dense ? CbTypography.labelXs : CbTypography.label;
    final showLabel =
        state == SshStepState.active || state == SshStepState.failed;
    return Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: iconSize,
          child: state == SshStepState.active
              ? Padding(
                  padding: const EdgeInsets.all(2),
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: color,
                  ),
                )
              : Icon(
                  switch (state) {
                    SshStepState.idle => PhosphorIconsLight.circleDashed,
                    SshStepState.done => PhosphorIconsLight.checkCircle,
                    SshStepState.failed => PhosphorIconsLight.xCircle,
                    SshStepState.active => PhosphorIconsLight.circle,
                  },
                  size: iconSize,
                  color: color,
                ),
        ),
        SizedBox(width: dense ? CbSpacing.xs : CbSpacing.xs + 2),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: title,
                  style: textStyle.copyWith(color: colors.textPrimary),
                ),
                if (showLabel)
                  TextSpan(
                    text: ' $label',
                    style: textStyle.copyWith(color: color),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
