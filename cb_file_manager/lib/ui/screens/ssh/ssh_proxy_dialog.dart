import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../config/translation_helper.dart';
import '../../../design_system/cb_design_system.dart';
import '../../../services/ssh/ssh_profile_store.dart';
import '../../components/common/connection_form_row.dart';
import '../../utils/route.dart';

Future<SshProxy?> showSshProxyDialog(
  BuildContext context,
  SshProfileStore store, {
  SshProxy? proxy,
}) => RouteUtils.showAcrylicDialog<SshProxy>(
  context: context,
  builder: (_) => SshProxyDialog(store: store, proxy: proxy),
);

class SshProxyDialog extends StatefulWidget {
  final SshProfileStore store;
  final SshProxy? proxy;
  const SshProxyDialog({super.key, required this.store, this.proxy});
  @override
  State<SshProxyDialog> createState() => _SshProxyDialogState();
}

class _SshProxyDialogState extends State<SshProxyDialog> {
  final _name = TextEditingController(),
      _host = TextEditingController(),
      _port = TextEditingController(),
      _user = TextEditingController(),
      _password = TextEditingController();
  late SshProxyType _type;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final p = widget.proxy;
    _type = p?.type ?? SshProxyType.socks5;
    _name.text = p?.name ?? '';
    _host.text = p?.host ?? '';
    _port.text = '${p?.port ?? 1080}';
    _user.text = p?.username ?? '';
    _password.text = p?.password ?? '';
  }

  @override
  void dispose() {
    for (final c in [_name, _host, _port, _user, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final proxy = SshProxy(
      id: widget.proxy?.id ?? const Uuid().v4(),
      name: _name.text.trim().isEmpty ? _host.text.trim() : _name.text.trim(),
      type: _type,
      host: _host.text.trim(),
      port: int.tryParse(_port.text) ?? 0,
      username: _user.text,
      password: _type == SshProxyType.socks4 ? '' : _password.text,
    );
    if (!proxy.isValid) {
      setState(() => _error = context.tr.sshProxyInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.saveProxy(proxy);
      if (mounted) Navigator.pop(context, proxy);
    } catch (_) {
      if (mounted) setState(() => _error = context.tr.sshImportSaveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return PopScope(
      canPop: !_busy,
      child: CbDialog(
        width: 680,
        title: widget.proxy == null ? tr.sshAddProxy : tr.sshEditProxy,
        icon: PhosphorIconsLight.globe,
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
            CbSelect<SshProxyType>(
              label: tr.sshProxyType,
              value: _type,
              expand: true,
              items: SshProxyType.values
                  .map(
                    (t) => CbSelectItem(
                      value: t,
                      label: switch (t) {
                        SshProxyType.httpConnect => 'HTTP CONNECT',
                        SshProxyType.socks5 => 'SOCKS5',
                        SshProxyType.socks4 => 'SOCKS4a',
                      },
                    ),
                  )
                  .toList(),
              onChanged: _busy
                  ? null
                  : (type) => setState(() {
                      if (_port.text == '1080' || _port.text == '8080') {
                        _port.text = type == SshProxyType.httpConnect
                            ? '8080'
                            : '1080';
                      }
                      _type = type;
                    }),
            ),
            const SizedBox(height: 12),
            ConnectionFormRow(
              firstFlex: 3,
              secondFlex: 1,
              first: CbTextField(
                controller: _host,
                label: tr.host,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
              ),
              second: CbTextField(
                controller: _port,
                label: tr.port,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
              ),
            ),
            const SizedBox(height: 12),
            ConnectionFormRow(
              first: CbTextField(
                controller: _user,
                label: tr.username,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
              ),
              second: _type == SshProxyType.socks4
                  ? const SizedBox.shrink()
                  : CbTextField(
                      controller: _password,
                      label: tr.password,
                      enabled: !_busy,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                    ),
            ),
            const SizedBox(height: 12),
            Text(tr.sshProxyHint),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: context.cbColors.status.danger),
                ),
              ),
          ],
        ),
        actions: [
          CbButton(
            label: tr.cancel,
            onPressed: _busy ? null : () => Navigator.pop(context),
          ),
          CbButton(
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
