import '../../../config/languages/app_localizations.dart';

/// The SSH workspace's sections. Each has its own tab path, so the
/// breadcrumb, Back and Up treat the sections like folders.
enum SshSection {
  hosts('#ssh'),
  keys('#ssh/keys'),
  knownHosts('#ssh/known-hosts'),
  proxies('#ssh/proxies'),
  forwards('#ssh/forwards');

  const SshSection(this.path);
  final String path;

  static SshSection? fromPath(String path) =>
      values.where((section) => section.path == path).firstOrNull;

  String label(AppLocalizations l10n) => switch (this) {
    hosts => l10n.sshHosts,
    keys => l10n.sshKeys,
    knownHosts => l10n.sshKnownHosts,
    proxies => l10n.sshProxies,
    forwards => l10n.sshPortForwarding,
  };
}
