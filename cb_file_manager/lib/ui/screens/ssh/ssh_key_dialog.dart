import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/translation_helper.dart';
import '../../../design_system/cb_design_system.dart';
import '../../../services/ssh/local_ssh_discovery.dart';
import '../../../services/ssh/ssh_profile_store.dart';
import '../../utils/route.dart';

Future<SshStoredKey?> showSshKeyDialog(
  BuildContext context, {
  required SshProfileStore store,
  bool generate = false,
  LocalSshKey? localKey,
  List<LocalSshKey> localKeys = const [],
}) => RouteUtils.showAcrylicDialog<SshStoredKey>(
  context: context,
  builder: (_) => _SshKeyDialog(
    store: store,
    generate: generate,
    localKey: localKey,
    localKeys: localKeys,
  ),
);

class _SshKeyDialog extends StatefulWidget {
  final SshProfileStore store;
  final bool generate;
  final LocalSshKey? localKey;
  final List<LocalSshKey> localKeys;
  const _SshKeyDialog({
    required this.store,
    required this.generate,
    this.localKey,
    required this.localKeys,
  });
  @override
  State<_SshKeyDialog> createState() => _SshKeyDialogState();
}

class _SshKeyDialogState extends State<_SshKeyDialog> {
  final _name = TextEditingController(),
      _pem = TextEditingController(),
      _pass = TextEditingController();
  String? _path, _error;
  bool _busy = false, _paste = false;
  @override
  void initState() {
    super.initState();
    if (widget.localKey != null) {
      _path = widget.localKey!.path;
      _name.text = widget.localKey!.name;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _pem.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = context.tr.sshRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      String pem = _pem.text;
      if (!widget.generate && !_paste && _path != null) {
        final file = File(_path!);
        if (await file.length() > 1024 * 1024) {
          throw const FormatException('Private key file is too large');
        }
        pem = await file.readAsString();
      }
      final key = widget.generate
          ? SshStoredKey.generate(_name.text)
          : SshStoredKey.import(
              _name.text,
              pem,
              _pass.text.isEmpty ? null : _pass.text,
            );
      final saved = await widget.store.importKey(key);
      if (mounted) Navigator.pop(context, saved);
    } catch (_) {
      if (mounted) setState(() => _error = context.tr.sshKeyImportFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return CbDialog(
      width: 720,
      title: widget.generate ? tr.sshGenerateKey : tr.sshImportKey,
      subtitle: widget.generate ? tr.sshGenerateHint : tr.sshImportHint,
      icon: PhosphorIconsLight.key,
      showCloseButton: !_busy,
      content: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CbTextField(
              controller: _name,
              enabled: !_busy,
              label: tr.sshDisplayName,
            ),
            const SizedBox(height: CbSpacing.xl),
            if (!widget.generate) ...[
              if (widget.localKeys.isNotEmpty) ...[
                CbSelect<String>(
                  label: tr.sshLocalKeys,
                  value: _path,
                  expand: true,
                  size: CbSelectSize.md,
                  items: widget.localKeys
                      .map(
                        (k) => CbSelectItem(
                          value: k.path,
                          label: k.name,
                          icon: PhosphorIconsLight.key,
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                          _path = v;
                          _paste = false;
                          _name.text = LocalSshKey(v).name;
                        }),
                ),
                const SizedBox(height: CbSpacing.lg),
              ],
              Wrap(
                spacing: CbSpacing.md,
                runSpacing: CbSpacing.sm,
                children: [
                  CbButton(
                    icon: PhosphorIconsLight.folderOpen,
                    label: tr.sshChooseKeyFile,
                    onPressed: _busy
                        ? null
                        : () async {
                            try {
                              final file = await FilePicker.pickFile();
                              if (!mounted || file?.path == null) return;
                              setState(() {
                                _path = file!.path;
                                _paste = false;
                                _name.text = file.name;
                              });
                            } catch (_) {
                              if (mounted) {
                                setState(() => _error = tr.sshKeyImportFailed);
                              }
                            }
                          },
                  ),
                  CbButton(
                    icon: PhosphorIconsLight.clipboardText,
                    label: tr.sshPasteKey,
                    onPressed: _busy
                        ? null
                        : () => setState(() => _paste = !_paste),
                  ),
                ],
              ),
              if (!_paste && _path != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: CbSpacing.md),
                  child: SelectableText(_path!),
                ),
              if (_paste)
                CbTextField(
                  controller: _pem,
                  enabled: !_busy,
                  maxLines: 7,
                  autocorrect: false,
                  enableSuggestions: false,
                  label: tr.sshPrivateKey,
                ),
              const SizedBox(height: CbSpacing.lg),
              CbTextField(
                controller: _pass,
                enabled: !_busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                label: tr.sshPassphrase,
                helperText: tr.sshPassphraseHint,
              ),
              const SizedBox(height: CbSpacing.lg),
            ],
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
      actions: [
        CbButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          label: tr.cancel,
        ),
        CbButton(
          variant: CbButtonVariant.primary,
          loading: _busy,
          onPressed: _busy ? null : _submit,
          label: tr.save,
        ),
      ],
    );
  }
}
