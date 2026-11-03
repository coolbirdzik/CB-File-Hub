import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../config/translation_helper.dart';
import '../../../design_system/cb_design_system.dart';
import '../../../helpers/core/text_utils.dart';
import '../../../services/ssh/ssh_profile_store.dart';
import '../../components/common/connection_form_row.dart';
import '../../utils/route.dart';

Future<SshForward?> showSshForwardDialog(
  BuildContext context,
  SshProfileStore store, {
  SshForward? forward,
  String? profileId,
}) => RouteUtils.showAcrylicDialog<SshForward>(
  context: context,
  builder: (_) =>
      SshForwardDialog(store: store, forward: forward, profileId: profileId),
);

class SshForwardDialog extends StatefulWidget {
  final SshProfileStore store;
  final SshForward? forward;

  /// Preselected host for a new rule.
  final String? profileId;
  const SshForwardDialog({
    super.key,
    required this.store,
    this.forward,
    this.profileId,
  });
  @override
  State<SshForwardDialog> createState() => _SshForwardDialogState();
}

class _SshForwardDialogState extends State<SshForwardDialog> {
  final _name = TextEditingController(),
      _bindHost = TextEditingController(),
      _bindPort = TextEditingController(),
      _targetHost = TextEditingController(),
      _targetPort = TextEditingController();
  late SshForwardType _type;
  String? _profileId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final f = widget.forward;
    _type = f?.type ?? SshForwardType.local;
    _profileId = f?.profileId ?? widget.profileId;
    _name.text = f?.name ?? '';
    _bindHost.text = f?.bindHost ?? '127.0.0.1';
    _bindPort.text = f == null ? '' : '${f.bindPort}';
    _targetHost.text = f?.targetHost ?? 'localhost';
    _targetPort.text = f == null || f.targetPort == 0 ? '' : '${f.targetPort}';
    // The network-exposure warning follows the listen address as it is typed.
    _bindHost.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    for (final c in [_name, _bindHost, _bindPort, _targetHost, _targetPort]) {
      c.dispose();
    }
    super.dispose();
  }

  SshForward get _draft => SshForward(
    id: widget.forward?.id ?? const Uuid().v4(),
    name: _name.text.trim(),
    profileId: _profileId ?? '',
    type: _type,
    bindHost: _bindHost.text.trim(),
    bindPort: int.tryParse(_bindPort.text.trim()) ?? 0,
    targetHost: _type == SshForwardType.dynamic ? '' : _targetHost.text.trim(),
    targetPort: _type == SshForwardType.dynamic
        ? 0
        : int.tryParse(_targetPort.text.trim()) ?? 0,
  );

  Future<void> _save() async {
    final forward = _draft;
    if (!forward.isValid) {
      setState(() => _error = context.tr.sshForwardInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.saveForward(forward);
      if (mounted) Navigator.pop(context, forward);
    } catch (_) {
      if (mounted) setState(() => _error = context.tr.sshImportSaveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final c = context.cbColors;
    final profiles = [...widget.store.profiles]
      ..sort((a, b) => TextUtils.compareNatural(a.name, b.name));
    final hint = switch (_type) {
      SshForwardType.local => tr.sshForwardLocalHint,
      SshForwardType.remote => tr.sshForwardRemoteHint,
      SshForwardType.dynamic => tr.sshForwardDynamicHint,
    };
    return PopScope(
      canPop: !_busy,
      child: CbDialog(
        width: 640,
        title: widget.forward == null ? tr.sshAddForward : tr.sshEditForward,
        icon: PhosphorIconsLight.arrowsLeftRight,
        showCloseButton: !_busy,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CbTextField(
              controller: _name,
              label: tr.sshDisplayName,
              enabled: !_busy,
            ),
            const SizedBox(height: 12),
            ConnectionFormRow(
              first: CbSelect<String>(
                key: const ValueKey('ssh-forward-host'),
                label: tr.sshForwardVia,
                value: _profileId,
                placeholder: tr.sshChooseHost,
                expand: true,
                searchable: profiles.length > 8,
                items: [
                  for (final p in profiles)
                    CbSelectItem(
                      value: p.id,
                      label: '${p.name}  ·  ${p.username}@${p.host}',
                      triggerLabel: p.name,
                      keywords: '${p.host} ${p.username} ${p.group}',
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (id) => setState(() => _profileId = id),
              ),
              second: CbSelect<SshForwardType>(
                key: const ValueKey('ssh-forward-type'),
                label: tr.sshForwardType,
                value: _type,
                expand: true,
                items: [
                  for (final t in SshForwardType.values)
                    CbSelectItem(
                      value: t,
                      label: switch (t) {
                        SshForwardType.local => tr.sshForwardLocal,
                        SshForwardType.remote => tr.sshForwardRemote,
                        SshForwardType.dynamic => tr.sshForwardDynamic,
                      },
                    ),
                ],
                onChanged: _busy ? null : (t) => setState(() => _type = t),
              ),
            ),
            const SizedBox(height: 12),
            ConnectionFormRow(
              firstFlex: 3,
              secondFlex: 1,
              first: CbTextField(
                key: const ValueKey('ssh-forward-bind-host'),
                controller: _bindHost,
                label: tr.sshBindAddress,
                enabled: !_busy,
                mono: true,
                autocorrect: false,
                enableSuggestions: false,
              ),
              second: CbTextField(
                key: const ValueKey('ssh-forward-bind-port'),
                controller: _bindPort,
                label: tr.sshBindPort,
                enabled: !_busy,
                mono: true,
                keyboardType: TextInputType.number,
                autocorrect: false,
                enableSuggestions: false,
              ),
            ),
            if (_type != SshForwardType.dynamic) ...[
              const SizedBox(height: 12),
              ConnectionFormRow(
                firstFlex: 3,
                secondFlex: 1,
                first: CbTextField(
                  key: const ValueKey('ssh-forward-target-host'),
                  controller: _targetHost,
                  label: tr.sshTargetHost,
                  enabled: !_busy,
                  mono: true,
                  autocorrect: false,
                  enableSuggestions: false,
                ),
                second: CbTextField(
                  key: const ValueKey('ssh-forward-target-port'),
                  controller: _targetPort,
                  label: tr.sshTargetPort,
                  enabled: !_busy,
                  mono: true,
                  keyboardType: TextInputType.number,
                  autocorrect: false,
                  enableSuggestions: false,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              hint,
              style: CbTypography.bodySm.copyWith(color: c.textSecondary),
            ),
            // A remote listener is on the server, where GatewayPorts decides.
            if (_type != SshForwardType.remote &&
                _bindHost.text.trim().isNotEmpty &&
                _draft.exposesNetwork)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      PhosphorIconsLight.warning,
                      size: CbSizes.iconMd,
                      color: c.status.warning,
                    ),
                    const SizedBox(width: CbSpacing.sm),
                    Expanded(
                      child: Text(
                        tr.sshForwardExposedWarning,
                        style: CbTypography.bodySm.copyWith(
                          color: c.status.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: c.status.danger)),
              ),
          ],
        ),
        actions: [
          CbButton(
            label: tr.cancel,
            onPressed: _busy ? null : () => Navigator.pop(context),
          ),
          CbButton(
            key: const ValueKey('ssh-forward-save'),
            label: tr.save,
            variant: CbButtonVariant.primary,
            onPressed: _busy ? null : _save,
            loading: _busy,
          ),
        ],
      ),
    );
  }
}
