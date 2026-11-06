import 'dart:io';

import 'package:flutter/material.dart';
import '../../../design_system/cb_design_system.dart';

import '../../../config/translation_helper.dart';
import '../../../services/desktop_integration/default_file_manager_service.dart';

class DefaultFileManagerSettings extends StatefulWidget {
  final DefaultFileManagerService? service;

  /// Lets onboarding block dismissal only during OS mutations, not status reads.
  final ValueNotifier<bool>? busy;
  final ValueChanged<FolderDefaultStatus>? onStatusChanged;
  const DefaultFileManagerSettings({
    super.key,
    this.service,
    this.busy,
    this.onStatusChanged,
  });

  @override
  State<DefaultFileManagerSettings> createState() =>
      _DefaultFileManagerSettingsState();
}

class _DefaultFileManagerSettingsState extends State<DefaultFileManagerSettings>
    with WidgetsBindingObserver {
  late final _service = widget.service ?? DefaultFileManagerService.instance;
  FolderDefaultStatus? _status;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _refresh();
  }

  Future<void> _refresh() => _run(() async {});

  Future<void> _run(
    Future<void> Function() action, {
    bool changesDefaults = false,
  }) async {
    if (_busy) return;
    widget.busy?.value = changesDefaults;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      final status = await _service.status();
      if (mounted) {
        setState(() => _status = status);
        widget.onStatusChanged?.call(status);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _status = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.busy?.value = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.tr;
    final status = _status;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Platform.isWindows
                ? l10n.defaultFileManagerWindowsDescription
                : l10n.defaultFileManagerDescription,
          ),
          const SizedBox(height: 12),
          if (status != null)
            Text(
              !status.available
                  ? l10n.defaultFileManagerUnavailable
                  : status.enabled
                  ? l10n.defaultFileManagerActive
                  : status.partial
                  ? l10n.defaultFileManagerPartial
                  : l10n.defaultFileManagerInactive,
            ),
          if (_error != null)
            SelectableText(
              '${l10n.defaultFileManagerFailed}\n$_error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_busy) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              CbButton(
                variant: CbButtonVariant.primary,
                onPressed:
                    _busy ||
                        status == null ||
                        !status.available ||
                        status.enabled ||
                        status.canRestore
                    ? null
                    : () => _run(_service.enable, changesDefaults: true),
                label: l10n.defaultFileManagerSet,
              ),
              if (status?.canRestore == true)
                CbButton(
                  onPressed: _busy
                      ? null
                      : () => _run(_service.restore, changesDefaults: true),
                  label: l10n.defaultFileManagerRestore,
                ),
              CbButton(
                variant: CbButtonVariant.ghost,
                onPressed: _busy ? null : _refresh,
                label: l10n.defaultFileManagerRefresh,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
