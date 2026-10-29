import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/translation_helper.dart';
import '../../../design_system/cb_design_system.dart';
import '../../../services/ssh/ssh_import.dart';
import '../../../services/ssh/ssh_client_scanner.dart';
import '../../../services/ssh/ssh_profile_store.dart';
import '../../utils/route.dart';

Future<SshImportSummary?> showSshImportDialog(
  BuildContext context,
  SshProfileStore store, {
  SshClientScanner? scanner,
}) => RouteUtils.showAcrylicDialog<SshImportSummary>(
  context: context,
  barrierDismissible: false,
  builder: (_) => SshImportDialog(store: store, scanner: scanner),
);

class SshImportDialog extends StatefulWidget {
  final SshProfileStore store;
  final SshClientScanner? scanner;
  const SshImportDialog({super.key, required this.store, this.scanner});
  @override
  State<SshImportDialog> createState() => _SshImportDialogState();
}

class _ImportRequest {
  final List<SshImportFile> files;
  final SshImportFormat format;
  final String passphrase, username;
  final List<SshStoredKey> existing;
  const _ImportRequest(
    this.files,
    this.format,
    this.passphrase,
    this.existing,
    this.username,
  );
}

SshImportPreview _parseImport(_ImportRequest request) => SshImporter.parse(
  request.files,
  format: request.format,
  passphrase: request.passphrase,
  existingKeys: request.existing,
  defaultUsername: request.username,
);

Future<List<SshClientScanResult>> _scanClients(_ImportRequest request) =>
    SshClientScanner().scan(
      passphrase: request.passphrase,
      existingKeys: request.existing,
    );

class _SshImportDialogState extends State<SshImportDialog> {
  final _text = TextEditingController(), _passphrase = TextEditingController();
  final _files = <SshImportFile>[];
  final _hosts = <String>{}, _keys = <String>{}, _proxies = <String>{};
  var _format = SshImportFormat.auto;
  SshImportPreview? _preview;
  bool _busy = false, _paste = false;
  bool _manual = false;
  List<SshClientScanResult> _sources = [];
  final _selectedSources = <int>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    _scanInstalled();
  }

  void _selectSources() {
    final previews = [
      for (final index in _selectedSources) _sources[index].preview,
    ];
    _preview = SshImportPreview(
      [for (final p in previews) ...p.hosts],
      [for (final p in previews) ...p.keys],
      [for (final p in previews) ...p.issues],
      proxies: [for (final p in previews) ...p.proxies],
    );
    _hosts
      ..clear()
      ..addAll(_preview!.hosts.map((h) => h.id));
    _keys
      ..clear()
      ..addAll(_preview!.keys.map((k) => k.id));
    _proxies
      ..clear()
      ..addAll(_preview!.proxies.map((p) => p.id));
  }

  Future<void> _scanInstalled() async {
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
    });
    try {
      await widget.store.load();
      final results = widget.scanner != null
          ? await widget.scanner!.scan(
              passphrase: _passphrase.text,
              existingKeys: widget.store.keys,
            )
          : await compute(
              _scanClients,
              _ImportRequest(
                const [],
                SshImportFormat.auto,
                _passphrase.text,
                widget.store.keys,
                '',
              ),
            );
      if (!mounted) return;
      setState(() {
        _sources = results;
        _selectedSources
          ..clear()
          ..addAll([
            for (var i = 0; i < results.length; i++)
              if (results[i].status == SshClientScanStatus.ready) i,
          ]);
        _selectSources();
      });
    } catch (_) {
      if (mounted) setState(() => _error = context.tr.sshImportReadFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _passphrase.dispose();
    super.dispose();
  }

  void _invalidate() => setState(() {
    _preview = null;
    _error = null;
    _hosts.clear();
    _keys.clear();
    _proxies.clear();
  });

  Future<void> _pick() async {
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.pickFiles();
      if (!mounted || picked.isEmpty) return;
      if (_files.length + picked.length > SshImporter.maxFiles) {
        setState(() => _error = context.tr.sshImportLimit);
        return;
      }
      final loaded = <SshImportFile>[];
      var totalBytes = _files.fold(
        0,
        (n, f) => n + utf8.encode(f.content).length,
      );
      for (final selected in picked) {
        if (selected.path == null) continue;
        final file = File(selected.path!);
        if (await file.length() > SshImporter.maxFileBytes) {
          throw const FormatException();
        }
        final bytes = await file.readAsBytes();
        totalBytes += bytes.length;
        if (totalBytes > SshImporter.maxTotalBytes) {
          throw const FormatException();
        }
        // Windows .reg exports normally use UTF-16LE with a BOM.
        final String text;
        if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
          if (bytes.length.isOdd) throw const FormatException();
          text = String.fromCharCodes([
            for (var i = 2; i < bytes.length; i += 2)
              bytes[i] | (bytes[i + 1] << 8),
          ]);
        } else {
          text = utf8.decode(bytes);
        }
        loaded.add(SshImportFile(selected.path!, text));
      }
      if (!mounted) return;
      _invalidate();
      setState(() {
        for (final file in loaded) {
          _files.removeWhere((f) => f.name == file.name);
          _files.add(file);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = context.tr.sshImportReadFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _inspect() async {
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
    });
    try {
      final files = [
        ..._files,
        if (_paste && _text.text.trim().isNotEmpty)
          SshImportFile(context.tr.sshImportPaste, _text.text),
      ];
      final format = _format;
      final passphrase = _passphrase.text;
      final existing = widget.store.keys;
      final username =
          Platform.environment['USERNAME'] ??
          Platform.environment['USER'] ??
          '';
      final preview = await compute(
        _parseImport,
        _ImportRequest(files, format, passphrase, existing, username),
      );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _hosts
          ..clear()
          ..addAll(preview.hosts.map((h) => h.id));
        _keys
          ..clear()
          ..addAll(preview.keys.map((k) => k.id));
        _proxies
          ..clear()
          ..addAll(preview.proxies.map((p) => p.id));
      });
    } catch (_) {
      if (mounted) setState(() => _error = context.tr.sshImportReadFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Set<String> get _requiredKeys => {
    for (final host in _preview?.hosts ?? <SshProfile>[])
      if (_hosts.contains(host.id) && host.keyId != null) host.keyId!,
  };
  Set<String> get _requiredProxies => {
    for (final host in _preview?.hosts ?? <SshProfile>[])
      if (_hosts.contains(host.id) && host.proxyId != null) host.proxyId!,
  };

  Future<void> _save() async {
    final preview = _preview;
    if (preview == null) return;
    final requiredKeys = _requiredKeys;
    final requiredProxies = _requiredProxies;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final summary = await widget.store.importProfiles(
        profiles: preview.hosts.where((h) => _hosts.contains(h.id)).toList(),
        keys: preview.keys
            .where((k) => _keys.contains(k.id) || requiredKeys.contains(k.id))
            .toList(),
        proxies: preview.proxies
            .where(
              (p) => _proxies.contains(p.id) || requiredProxies.contains(p.id),
            )
            .toList(),
      );
      if (mounted) Navigator.pop(context, summary);
    } catch (_) {
      if (mounted) setState(() => _error = context.tr.sshImportSaveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatName(SshImportFormat format) => switch (format) {
    SshImportFormat.auto => context.tr.sshImportAuto,
    SshImportFormat.termius => 'Termius (CSV / JSON / OpenSSH)',
    SshImportFormat.openSsh => 'OpenSSH config',
    SshImportFormat.putty => 'PuTTY (.reg)',
    SshImportFormat.winScp => 'WinSCP (.ini)',
    SshImportFormat.secureCrt => 'SecureCRT (.ini)',
    SshImportFormat.tabby => 'Tabby (YAML)',
  };

  String _problem(SshImportProblem problem) => switch (problem) {
    SshImportProblem.format => context.tr.sshImportUnknownFormat,
    SshImportProblem.invalidHost => context.tr.sshInvalidHost,
    SshImportProblem.invalidPort => context.tr.sshInvalidPort,
    SshImportProblem.key => context.tr.sshKeyImportFailed,
    SshImportProblem.missingKey => context.tr.sshImportMissingKey,
    SshImportProblem.proxy => context.tr.sshImportProxyFailed,
    SshImportProblem.unsupported => context.tr.sshImportUnsupported,
    SshImportProblem.password => context.tr.sshImportPasswordMissing,
    SshImportProblem.limit => context.tr.sshImportLimit,
  };

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final preview = _preview;
    final requiredKeys = _requiredKeys;
    return PopScope(
      canPop: !_busy,
      child: CbDialog(
        width: 780,
        title: tr.sshImportFromApp,
        subtitle: tr.sshImportAppHint,
        icon: PhosphorIconsLight.downloadSimple,
        showCloseButton: !_busy,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                CbButton(
                  label: tr.sshImportScan,
                  icon: PhosphorIconsLight.magnifyingGlass,
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() => _manual = false);
                          _scanInstalled();
                        },
                ),
                CbButton(
                  label: tr.sshImportFileMode,
                  icon: PhosphorIconsLight.folderOpen,
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() => _manual = !_manual);
                          _invalidate();
                          if (!_manual) setState(_selectSources);
                        },
                ),
              ],
            ),
            if (!_manual) ...[
              const SizedBox(height: 12),
              Text(tr.sshImportScanHint),
              for (var i = 0; i < _sources.length; i++)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_sources[i].app),
                  subtitle: Text(
                    '${switch (_sources[i].status) {
                      SshClientScanStatus.ready => '${tr.sshImportFound(_sources[i].preview.hosts.length, _sources[i].preview.keys.length)} · ${_sources[i].preview.proxies.length} ${tr.sshProxies}',
                      SshClientScanStatus.notFound => tr.sshImportNotFound,
                      SshClientScanStatus.keyUnavailable => tr.sshImportVaultLocked,
                      SshClientScanStatus.unreadable => tr.sshImportScanFailed,
                    }}${_sources[i].location.isEmpty ? '' : '\n${_sources[i].location}'}',
                  ),
                  value: _selectedSources.contains(i),
                  onChanged:
                      _busy || _sources[i].status != SshClientScanStatus.ready
                      ? null
                      : (selected) => setState(() {
                          selected == true
                              ? _selectedSources.add(i)
                              : _selectedSources.remove(i);
                          _selectSources();
                        }),
                ),
            ],
            if (_manual) ...[
              CbSelect<SshImportFormat>(
                label: tr.sshImportSource,
                value: _format,
                expand: true,
                items: SshImportFormat.values
                    .map((f) => CbSelectItem(value: f, label: _formatName(f)))
                    .toList(),
                onChanged: _busy
                    ? null
                    : (value) {
                        _format = value;
                        _invalidate();
                      },
              ),
              const SizedBox(height: 12),
              Text(tr.sshImportTermiusHint),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  CbButton(
                    label: tr.sshImportChooseFiles,
                    icon: PhosphorIconsLight.folderOpen,
                    onPressed: _busy ? null : _pick,
                  ),
                  CbButton(
                    label: tr.sshImportPaste,
                    icon: PhosphorIconsLight.clipboardText,
                    onPressed: _busy
                        ? null
                        : () {
                            _paste = !_paste;
                            _invalidate();
                          },
                  ),
                ],
              ),
              for (final file in _files)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: tr.delete,
                    icon: const Icon(Icons.close),
                    onPressed: _busy
                        ? null
                        : () {
                            _files.remove(file);
                            _invalidate();
                          },
                  ),
                ),
              if (_paste) ...[
                const SizedBox(height: 12),
                CbTextField(
                  controller: _text,
                  label: tr.sshImportPaste,
                  maxLines: 5,
                  enabled: !_busy,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) => _invalidate(),
                ),
              ],
            ],
            const SizedBox(height: 12),
            CbTextField(
              controller: _passphrase,
              label: tr.sshPassphrase,
              helperText: tr.sshImportPassphraseHint,
              obscureText: true,
              enabled: !_busy,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => _invalidate(),
            ),
            const SizedBox(height: 12),
            Text(tr.sshVaultHint),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: context.cbColors.status.danger),
                ),
              ),
            if (preview != null) ...[
              const Divider(height: 28),
              Text(
                tr.sshImportPreview,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (preview.hosts.isEmpty &&
                  preview.keys.isEmpty &&
                  preview.proxies.isEmpty)
                Text(tr.sshImportEmpty),
              if (preview.hosts.isNotEmpty)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr.sshHosts),
                  value: _hosts.length == preview.hosts.length,
                  onChanged: _busy
                      ? null
                      : (selected) => setState(() {
                          _hosts.clear();
                          if (selected == true) {
                            _hosts.addAll(preview.hosts.map((h) => h.id));
                          }
                        }),
                ),
              for (final h in preview.hosts)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _hosts.contains(h.id),
                  title: Text(h.name),
                  subtitle: Text(
                    '${h.username}@${h.host}:${h.port}${h.group.isEmpty ? '' : ' · ${h.group}'}${h.keyId == null ? '' : ' · ${tr.sshKeyAuth}'}${h.proxyId == null ? '' : ' · ${tr.sshProxy}'}',
                  ),
                  onChanged: _busy
                      ? null
                      : (selected) => setState(() {
                          selected == true
                              ? _hosts.add(h.id)
                              : _hosts.remove(h.id);
                        }),
                ),
              if (preview.keys.isNotEmpty)
                Text(
                  tr.sshKeys,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              for (final k in preview.keys)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _keys.contains(k.id) || requiredKeys.contains(k.id),
                  title: Text(k.name),
                  subtitle: Text(k.fingerprint),
                  onChanged: _busy || requiredKeys.contains(k.id)
                      ? null
                      : (selected) => setState(() {
                          selected == true
                              ? _keys.add(k.id)
                              : _keys.remove(k.id);
                        }),
                ),
              if (preview.proxies.isNotEmpty)
                Text(
                  tr.sshProxies,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              for (final proxy in preview.proxies)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(proxy.name),
                  subtitle: Text(
                    '${proxy.protocol} · ${proxy.host}:${proxy.port}',
                  ),
                  value:
                      _proxies.contains(proxy.id) ||
                      _requiredProxies.contains(proxy.id),
                  onChanged: _busy || _requiredProxies.contains(proxy.id)
                      ? null
                      : (selected) => setState(() {
                          selected == true
                              ? _proxies.add(proxy.id)
                              : _proxies.remove(proxy.id);
                        }),
                ),
              for (final issue in preview.issues)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${issue.item.isEmpty ? '' : '${issue.item}: '}${_problem(issue.problem)}',
                  ),
                ),
            ],
          ],
        ),
        actions: [
          CbButton(
            label: tr.cancel,
            onPressed: _busy ? null : () => Navigator.pop(context),
          ),
          if (_manual)
            CbButton(
              label: tr.sshImportPreview,
              onPressed:
                  _busy ||
                      (_files.isEmpty && (!_paste || _text.text.trim().isEmpty))
                  ? null
                  : _inspect,
            ),
          CbButton(
            label: tr.sshImportSelected,
            variant: CbButtonVariant.primary,
            onPressed:
                _busy ||
                    preview == null ||
                    (_hosts.isEmpty && _keys.isEmpty && _proxies.isEmpty)
                ? null
                : _save,
          ),
        ],
      ),
    );
  }
}
