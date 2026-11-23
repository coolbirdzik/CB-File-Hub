import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../design_system/cb_design_system.dart';
import '../../../services/network_browsing/desktop_smb_mounts.dart';
import '../../tab_manager/core/tab_manager.dart';
import '../system_screen.dart';

class MountedSmbBrowserScreen extends StatefulWidget {
  const MountedSmbBrowserScreen({super.key, required this.tabId});

  final String tabId;

  @override
  State<MountedSmbBrowserScreen> createState() =>
      _MountedSmbBrowserScreenState();
}

class _MountedSmbBrowserScreenState extends State<MountedSmbBrowserScreen> {
  Future<List<DesktopSmbMount>> _mounts = DesktopSmbMount.list();

  void _refresh() => setState(() => _mounts = DesktopSmbMount.list());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SystemScreen(
      tabId: widget.tabId,
      onRefresh: _refresh,
      title: l10n.smbNetwork,
      systemId: '#smb',
      icon: PhosphorIconsLight.desktop,
      showAppBar: true,
      actions: [
        CbButton.icon(
          icon: PhosphorIconsLight.arrowsClockwise,
          onPressed: _refresh,
          tooltip: l10n.refresh,
        ),
      ],
      child: FutureBuilder<List<DesktopSmbMount>>(
        future: _mounts,
        builder: (context, snapshot) {
          if (!snapshot.hasData &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final mounts = (snapshot.data ?? const <DesktopSmbMount>[])
              .where((mount) => !mount.uri.pathSegments.first.endsWith(r'$'))
              .toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (mounts.isEmpty) ...[
                Text(
                  l10n.noActiveSmbConnections,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(l10n.mountSmbShareHint),
              ],
              for (final mount in mounts)
                ListTile(
                  leading: const Icon(PhosphorIconsLight.folderSimple),
                  title: Text(
                    '${mount.uri.authority}/${mount.uri.pathSegments.join('/')}',
                  ),
                  subtitle: Text(mount.directory),
                  trailing: const Icon(PhosphorIconsLight.arrowRight),
                  onTap: () => context.read<TabManagerBloc>().add(
                    UpdateTabPath(widget.tabId, mount.directory),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
