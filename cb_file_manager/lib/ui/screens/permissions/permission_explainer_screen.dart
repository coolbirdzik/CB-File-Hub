import 'dart:io';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../services/permission_state_service.dart';

class PermissionExplainerScreen extends StatefulWidget {
  const PermissionExplainerScreen({Key? key}) : super(key: key);

  @override
  State<PermissionExplainerScreen> createState() =>
      _PermissionExplainerScreenState();
}

class _PermissionExplainerScreenState extends State<PermissionExplainerScreen> {
  bool _checking = true;
  bool _hasStorage = false;
  bool _hasAllFilesAccess = false;
  bool _hasInstallPackages = false;
  bool _hasLocalNet = true; // default true except iOS
  bool _notifGranted = false;

  @override
  void initState() {
    super.initState();
    _refreshStates();
  }

  Future<void> _refreshStates() async {
    setState(() => _checking = true);
    final svc = PermissionStateService.instance;
    final s = await svc.hasStorageOrPhotosPermission();
    final a = await svc.hasAllFilesAccessPermission();
    final i = await svc.hasInstallPackagesPermission();
    final n = await svc.hasNotificationsPermission();
    final ln = await svc.hasLocalNetworkPermission();
    setState(() {
      _hasStorage = s;
      _hasAllFilesAccess = a;
      _hasInstallPackages = i;
      _notifGranted = n;
      _hasLocalNet = ln;
      _checking = false;
    });
  }

  bool get _mandatorySatisfied {
    final storageOk = _hasStorage;
    final allFilesOk = Platform.isAndroid ? _hasAllFilesAccess : true;
    final installOk = Platform.isAndroid ? _hasInstallPackages : true;
    final localOk = Platform.isIOS ? _hasLocalNet : true;
    return storageOk && allFilesOk && installOk && localOk;
  }

  Future<void> _requestStorage() async {
    final ok = await PermissionStateService.instance.requestStorageOrPhotos();
    if (!ok) {
      await _openSettings();
    }
    await _refreshStates();
  }

  Future<void> _requestAllFilesAccess() async {
    final ok = await PermissionStateService.instance.requestAllFilesAccess();
    if (!ok) {
      await _openSettings();
    }
    await _refreshStates();
  }

  Future<void> _requestInstallPackages() async {
    final ok = await PermissionStateService.instance.requestInstallPackages();
    if (!ok) {
      await _openSettings();
    }
    await _refreshStates();
  }

  Future<void> _requestLocalNet() async {
    final ok = await PermissionStateService.instance.requestLocalNetwork();
    if (!ok) {
      await _openSettings();
    }
    await _refreshStates();
  }

  Future<void> _requestNotif() async {
    await PermissionStateService.instance.requestNotifications();
    await _refreshStates();
  }

  Future<void> _requestAllPermissions() async {
    setState(() => _checking = true);

    final svc = PermissionStateService.instance;

    // Request all permissions sequentially
    await svc.requestStorageOrPhotos();
    if (Platform.isAndroid) {
      await svc.requestAllFilesAccess();
      await svc.requestInstallPackages();
    }
    if (Platform.isIOS) {
      await svc.requestLocalNetwork();
    }
    await svc.requestNotifications();

    await _refreshStates();
  }

  Future<void> _openSettings() async {
    final uri =
        Platform.isIOS ? Uri.parse('app-settings:') : Uri.parse('package:');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final cards = <Widget>[
      _PermissionCard(
        title: l10n.storagePhotosPermission,
        description: l10n.storagePhotosDescription,
        granted: _hasStorage,
        onRequest: _requestStorage,
      ),
      if (Platform.isAndroid)
        _PermissionCard(
          title: l10n.allFilesAccessPermission,
          description: l10n.allFilesAccessDescription,
          granted: _hasAllFilesAccess,
          onRequest: _requestAllFilesAccess,
        ),
      if (Platform.isAndroid)
        _PermissionCard(
          title: l10n.installPackagesPermission,
          description: l10n.installPackagesDescription,
          granted: _hasInstallPackages,
          onRequest: _requestInstallPackages,
        ),
      if (Platform.isIOS)
        _PermissionCard(
          title: l10n.localNetworkPermission,
          description: l10n.localNetworkDescription,
          granted: _hasLocalNet,
          onRequest: _requestLocalNet,
        ),
      _PermissionCard(
        title: l10n.notificationsPermission,
        description: l10n.notificationsDescription,
        granted: _notifGranted,
        onRequest: _requestNotif,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.grantPermissionsToContinue)),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.permissionsDescription,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: cards.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => cards[i],
                    ),
                  ),
                  // Grant All Permissions button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _checking ? null : _requestAllPermissions,
                      icon: _checking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(PhosphorIconsLight.shieldCheck),
                      label: Text(_checking
                          ? l10n.grantingPermissions
                          : l10n.grantAllPermissions),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _mandatorySatisfied
                              ? () => Navigator.of(context).maybePop()
                              : null,
                          child: Text(l10n.enterApp),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          child: Text(l10n.skipEnterApp),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final String title;
  final String description;
  final bool granted;
  final VoidCallback onRequest;

  const _PermissionCard({
    Key? key,
    required this.title,
    required this.description,
    required this.granted,
    required this.onRequest,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              granted
                  ? PhosphorIconsLight.checkCircle
                  : PhosphorIconsLight.warningCircle,
              color: granted
                  ? Theme.of(context).colorScheme.tertiary
                  : Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(description),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: onRequest,
              child: Text(granted ? l10n.granted : l10n.grantPermission),
            )
          ],
        ),
      ),
    );
  }
}
