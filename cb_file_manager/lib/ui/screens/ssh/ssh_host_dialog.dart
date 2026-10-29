import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../config/translation_helper.dart';
import '../../../design_system/cb_design_system.dart';
import '../../../services/network_browsing/network_service_registry.dart';
import '../../../services/ssh/local_ssh_discovery.dart';
import '../../../services/ssh/ssh_profile_store.dart';
import '../../components/common/connection_form_row.dart';
import '../../utils/route.dart';
import 'ssh_key_dialog.dart';
import 'ssh_proxy_dialog.dart';

Future<bool> promptSshHostTrust(
  BuildContext context,
  String host,
  int port,
  String type,
  String fingerprint,
  String? previous,
) async {
  if (!context.mounted) return false;
  return await RouteUtils.showAcrylicDialog<bool>(
        context: context,
        builder: (context) => CbDialog(
          width: 640,
          icon: PhosphorIconsLight.fingerprint,
          destructive: previous != null,
          title: previous == null
              ? context.tr.sshTrustHost
              : context.tr.sshHostKeyChanged,
          content: SizedBox(
            width: double.infinity,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$host:$port · $type'),
                  const SizedBox(height: CbSpacing.lg),
                  SelectableText(
                    fingerprint,
                    style: CbTypography.mono.copyWith(
                      color: context.cbColors.textPrimary,
                    ),
                  ),
                  if (previous != null) ...[
                    const SizedBox(height: CbSpacing.md),
                    SelectableText(
                      previous,
                      style: TextStyle(
                        color: context.cbColors.status.danger,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ],
                  const SizedBox(height: CbSpacing.lg),
                  Text(context.tr.sshVerifyFingerprint),
                ],
              ),
            ),
          ),
          actions: [
            CbButton(
              onPressed: () => Navigator.pop(context, false),
              label: context.tr.cancel,
            ),
            CbButton(
              variant: CbButtonVariant.primary,
              onPressed: () => Navigator.pop(context, true),
              label: context.tr.sshTrustAndConnect,
            ),
          ],
        ),
      ) ??
      false;
}

class SshHostDialog extends StatefulWidget {
  final SshProfile? profile;
  final bool connectSftp;
  final ValueChanged<String>? onConnected;
  final String? initialHost;
  final SshProfileStore? store;
  final LocalSshDiscovery? discovery;
  final LocalSshHost? localHost;
  final VoidCallback? onChangeService;
  const SshHostDialog({
    super.key,
    this.profile,
    this.connectSftp = false,
    this.onConnected,
    this.initialHost,
    this.store,
    this.discovery,
    this.localHost,
    this.onChangeService,
  });
  @override
  State<SshHostDialog> createState() => _SshHostDialogState();
}

class _SshHostDialogState extends State<SshHostDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _host = TextEditingController(),
      _user = TextEditingController(),
      _password = TextEditingController(),
      _port = TextEditingController(),
      _group = TextEditingController();
  late final _store = widget.store ?? SshProfileStore.instance;
  late final _discovery = widget.discovery ?? LocalSshDiscovery();
  LocalSshSnapshot _local = const LocalSshSnapshot();
  LocalSshKey? _localKey;
  LocalSshHost? _selectedHost;
  bool _scanning = true;

  bool _keyAuth = false, _busy = false, _loaded = false, _save = true;
  String? _keyId, _proxyId, _error;
  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _name.text = p?.name ?? '';
    _host.text = p?.host ?? widget.initialHost ?? '';
    _user.text = p?.username ?? '';
    _password.text = p?.password ?? '';
    _port.text = '${p?.port ?? 22}';
    _group.text = p?.group ?? '';
    _keyId = p?.keyId;
    _proxyId = p?.proxyId;
    _keyAuth = _keyId != null;
    _load();
  }

  Future<void> _load() async {
    final initial = [
      _name.text,
      _host.text,
      _user.text,
      _port.text,
      _password.text,
      _group.text,
      '$_keyAuth',
      _keyId ?? '',
    ];
    try {
      await _store.load();
      if (mounted) setState(() => _loaded = true);
      final local = await _discovery.scan();
      if (!mounted) return;
      setState(() {
        _local = local;
        final current = [
          _name.text,
          _host.text,
          _user.text,
          _port.text,
          _password.text,
          _group.text,
          '$_keyAuth',
          _keyId ?? '',
        ];
        if (widget.profile == null &&
            List.generate(
              initial.length,
              (i) => initial[i] == current[i],
            ).every((v) => v)) {
          final matches = local.hosts.where(
            (h) => h.alias == _host.text || h.host == _host.text,
          );
          final suggestion =
              widget.localHost ??
              (matches.isNotEmpty
                  ? matches.first
                  : local.hosts.length == 1 && _host.text.isEmpty
                  ? local.hosts.single
                  : null);
          if (suggestion != null) _applyHost(suggestion);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _applyHost(LocalSshHost host) {
    _selectedHost = host;
    _name.text = host.alias;
    _host.text = host.host;
    _user.text = host.username;
    _port.text = '${host.port}';
    _password.clear();
    _keyId = null;
    final keys = host.identityFiles.expand(
      (path) => _local.keys.where((key) => key.path == path),
    );
    _localKey = keys.isEmpty ? null : keys.first;
    _keyAuth = _localKey != null;
    _error = null;
  }

  Future<void> _addKey({bool generate = false, LocalSshKey? localKey}) async {
    final key = await showSshKeyDialog(
      context,
      store: _store,
      generate: generate,
      localKey: localKey,
      localKeys: _local.keys,
    );
    if (key != null && mounted) {
      setState(() {
        _keyAuth = true;
        _keyId = key.id;
        _localKey = null;
        _error = null;
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _host, _user, _password, _port, _group]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_keyAuth && _localKey != null) {
      await _addKey(localKey: _localKey);
      if (!mounted || _localKey != null) return;
    }
    if (_keyAuth && _keyId == null) {
      setState(() => _error = context.tr.sshNoKeys);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final p = SshProfile(
      id: widget.profile?.id ?? const Uuid().v4(),
      name: _name.text.trim().isEmpty ? _host.text.trim() : _name.text.trim(),
      host: _host.text.trim(),
      username: _user.text.trim(),
      port: int.parse(_port.text),
      password: _keyAuth ? '' : _password.text,
      keyId: _keyAuth ? _keyId : null,
      group: _group.text.trim(),
      proxyId: _proxyId,
    );
    try {
      if (widget.connectSftp) {
        final result = await NetworkServiceRegistry().connect(
          serviceName: 'SFTP',
          host: p.host,
          username: p.username,
          password: p.password,
          port: p.port,
          additionalOptions: {
            'keyId': p.keyId,
            'proxyId': p.proxyId,
            'trustPrompt':
                (String h, int port, String type, String fp, String? old) =>
                    promptSshHostTrust(context, h, port, type, fp, old),
          },
        );
        if (!result.success) {
          throw StateError(result.errorMessage ?? 'SFTP connection failed');
        }
        if (_save) await _store.saveProfile(p);
        if (!mounted) return;
        widget.onConnected?.call(result.connectedPath!);
      } else {
        await _store.saveProfile(p);
      }
      if (mounted) Navigator.pop(context, p);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    Widget field(
      TextEditingController controller,
      String label, {
      bool required = false,
      bool secret = false,
      String? Function(String?)? validator,
    }) => FormField<String>(
      initialValue: controller.text,
      validator: (_) =>
          validator?.call(controller.text) ??
          (required && controller.text.trim().isEmpty ? tr.sshRequired : null),
      builder: (state) => CbTextField(
        controller: controller,
        label: label,
        enabled: !_busy,
        obscureText: secret,
        autocorrect: false,
        enableSuggestions: !secret,
        errorText: state.errorText,
        onChanged: state.didChange,
      ),
    );
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: CbSpacing.xl, bottom: CbSpacing.lg),
      child: Text(
        text,
        style: CbTypography.headingSm.copyWith(
          color: context.cbColors.textPrimary,
        ),
      ),
    );
    return CbDialog(
      width: 800,
      icon: PhosphorIconsLight.terminalWindow,
      title: widget.connectSftp
          ? tr.connectToServiceServer('SFTP')
          : widget.profile == null
          ? tr.sshAddHost
          : tr.sshEditHost,
      showCloseButton: !_busy,
      content: SizedBox(
        width: double.infinity,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.onChangeService != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: CbButton(
                    onPressed: _busy ? null : widget.onChangeService,
                    icon: PhosphorIconsLight.arrowLeft,
                    label: tr.serviceType,
                  ),
                ),
              if (_scanning) const LinearProgressIndicator(),
              if (_local.hosts.isNotEmpty) ...[
                CbSelect<String>(
                  key: const ValueKey('ssh-config-host'),
                  label: tr.sshLocalConfig,
                  placeholder: tr.sshLocalConfigHint,
                  value: _selectedHost?.alias,
                  expand: true,
                  size: CbSelectSize.md,
                  items: _local.hosts
                      .map(
                        (h) => CbSelectItem(
                          value: h.alias,
                          label: '${h.alias}  ·  ${h.username}@${h.host}',
                          triggerLabel: h.alias,
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (v) => setState(
                          () => _applyHost(
                            _local.hosts.firstWhere((h) => h.alias == v),
                          ),
                        ),
                ),
              ] else if (!_scanning)
                Text(
                  tr.sshNoLocalConfig,
                  style: CbTypography.caption.copyWith(
                    color: context.cbColors.textSecondary,
                  ),
                ),
              if (_local.warnings.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: CbSpacing.md),
                  child: Text(tr.sshDiscoveryIncomplete),
                ),
              if (_selectedHost?.unsupportedOptions.isNotEmpty ?? false)
                Padding(
                  padding: const EdgeInsets.only(top: CbSpacing.md),
                  child: Text(
                    tr.sshConfigUnsupported,
                    style: TextStyle(color: context.cbColors.status.danger),
                  ),
                ),
              heading(tr.sshConnectionDetails),
              ConnectionFormRow(
                firstFlex: 3,
                secondFlex: 1,
                first: field(
                  _host,
                  tr.host,
                  validator: (v) =>
                      v == null ||
                          v.trim().isEmpty ||
                          v.contains(RegExp(r'[\s/@]')) ||
                          v.contains('://')
                      ? tr.sshInvalidHost
                      : null,
                ),
                second: field(
                  _port,
                  tr.port,
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    return n == null || n < 1 || n > 65535
                        ? tr.sshInvalidPort
                        : null;
                  },
                ),
              ),
              const SizedBox(height: CbSpacing.lg),
              ConnectionFormRow(
                first: field(_name, tr.sshDisplayName),
                second: field(_group, tr.sshGroup),
              ),
              heading(tr.sshProxy),
              CbSelect<String>(
                key: const ValueKey('ssh-proxy'),
                label: tr.sshProxy,
                value: _proxyId ?? '',
                expand: true,
                items: [
                  CbSelectItem(value: '', label: tr.sshProxyNone),
                  ..._store.proxies.map(
                    (p) => CbSelectItem(
                      value: p.id,
                      label: '${p.name} · ${p.protocol}',
                    ),
                  ),
                ],
                onChanged: _busy || !_loaded
                    ? null
                    : (v) => setState(() => _proxyId = v.isEmpty ? null : v),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  CbButton(
                    label: tr.sshAddProxy,
                    onPressed: _busy || !_loaded
                        ? null
                        : () async {
                            final proxy = await showSshProxyDialog(
                              context,
                              _store,
                            );
                            if (proxy != null && mounted) {
                              setState(() => _proxyId = proxy.id);
                            }
                          },
                  ),
                  if (_proxyId != null)
                    CbButton(
                      label: tr.sshEditProxy,
                      onPressed: _busy
                          ? null
                          : () async {
                              final current = _store.proxies
                                  .where((p) => p.id == _proxyId)
                                  .firstOrNull;
                              if (current != null) {
                                await showSshProxyDialog(
                                  context,
                                  _store,
                                  proxy: current,
                                );
                                if (mounted) setState(() {});
                              }
                            },
                    ),
                ],
              ),
              heading(tr.sshAuthMethod),
              ConnectionFormRow(
                first: field(_user, tr.username, required: true),
                second: CbSelect<bool>(
                  label: tr.sshAuthMethod,
                  value: _keyAuth,
                  expand: true,
                  size: CbSelectSize.md,
                  items: [
                    CbSelectItem(value: false, label: tr.sshPasswordAuth),
                    CbSelectItem(value: true, label: tr.sshKeyAuth),
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _keyAuth = v),
                ),
              ),
              const SizedBox(height: CbSpacing.lg),
              if (_keyAuth) ...[
                CbSelect<String>(
                  key: const ValueKey('ssh-auth-key'),
                  label: tr.sshKeys,
                  value: _localKey != null
                      ? 'local:${_localKey!.path}'
                      : _keyId,
                  placeholder: tr.sshImportKey,
                  expand: true,
                  size: CbSelectSize.md,
                  items: [
                    ..._store.keys.map(
                      (k) => CbSelectItem(value: k.id, label: k.name),
                    ),
                    ..._local.keys.map(
                      (k) => CbSelectItem(
                        value: 'local:${k.path}',
                        label: '${k.name} · ~/.ssh',
                      ),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                          _localKey = v.startsWith('local:')
                              ? _local.keys.firstWhere(
                                  (k) => 'local:${k.path}' == v,
                                )
                              : null;
                          _keyId = _localKey == null ? v : null;
                        }),
                ),
                if (_localKey != null)
                  Padding(
                    padding: const EdgeInsets.only(top: CbSpacing.sm),
                    child: Text(
                      tr.sshLocalKeyPending,
                      style: CbTypography.caption.copyWith(
                        color: context.cbColors.textSecondary,
                      ),
                    ),
                  ),
              ] else
                field(_password, tr.password, secret: true),
              const SizedBox(height: CbSpacing.md),
              Wrap(
                spacing: CbSpacing.md,
                runSpacing: CbSpacing.sm,
                children: [
                  CbButton(
                    icon: PhosphorIconsLight.fileArrowUp,
                    label: tr.sshImportKey,
                    onPressed: _busy || !_loaded ? null : () => _addKey(),
                  ),
                  CbButton(
                    icon: PhosphorIconsLight.key,
                    label: tr.sshGenerateKey,
                    onPressed: _busy || !_loaded
                        ? null
                        : () => _addKey(generate: true),
                  ),
                ],
              ),
              if (widget.connectSftp)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr.saveCredentials),
                  value: _save,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _save = v ?? false),
                ),
              const SizedBox(height: CbSpacing.md),
              Text(
                tr.sshVaultHint,
                style: CbTypography.caption.copyWith(
                  color: context.cbColors.textSecondary,
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: CbSpacing.lg),
                  child: Text(
                    _error!,
                    style: TextStyle(color: context.cbColors.status.danger),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        CbButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          label: tr.cancel,
        ),
        CbButton(
          variant: CbButtonVariant.primary,
          onPressed: _busy || !_loaded || _scanning ? null : _submit,
          loading: _busy,
          label: widget.connectSftp ? tr.connect : tr.save,
        ),
      ],
    );
  }
}
