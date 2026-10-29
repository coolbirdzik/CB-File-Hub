import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../design_system/cb_design_system.dart';

/// What a host avatar shows: a recognised kind of machine, or initials.
typedef SshHostGlyph = ({IconData? icon, String initials, double hue});

/// Keywords are whole words with trailing digits removed, so `web01` and
/// `db2` match while `api` never matches `pi`. Earlier kinds win: a service
/// beats the operating system under it, and a recognisable platform beats a
/// generic word such as `build`, `vps` or `dev`.
const List<(IconData, double, String)> _kinds = [
  (PhosphorIconsLight.cpu, 340, 'raspberry rpi raspi pi jetson arduino esp'),
  (PhosphorIconsLight.githubLogo, 270, 'github'),
  (PhosphorIconsLight.gitlabLogo, 18, 'gitlab'),
  (
    PhosphorIconsLight.database,
    42,
    'db database postgres postgresql pg mysql mariadb mongo mongodb redis sql '
        'mssql elastic clickhouse cassandra',
  ),
  (
    PhosphorIconsLight.cube,
    200,
    'docker k8s kube kubernetes container swarm podman rancher portainer lxc '
        'proxmox',
  ),
  (
    PhosphorIconsLight.hardDrives,
    160,
    'nas storage backup synology truenas unraid qnap minio',
  ),
  (
    PhosphorIconsLight.shieldCheck,
    0,
    'firewall pfsense opnsense vpn wireguard openvpn bastion jump jumphost '
        'gateway gw router mikrotik openwrt',
  ),
  (
    PhosphorIconsLight.chartLine,
    55,
    'grafana prometheus monitor monitoring metrics zabbix kibana',
  ),
  (PhosphorIconsLight.brain, 315, 'ai gpu ml llm ollama'),
  (PhosphorIconsLight.envelope, 300, 'mail smtp imap postfix'),
  (PhosphorIconsLight.gameController, 285, 'game minecraft steam'),
  (PhosphorIconsLight.windowsLogo, 212, 'windows win rdp'),
  (
    PhosphorIconsLight.appleLogo,
    260,
    'mac macos macbook macmini imac osx apple',
  ),
  (PhosphorIconsLight.androidLogo, 135, 'android termux'),
  (
    PhosphorIconsLight.linuxLogo,
    28,
    'linux ubuntu debian centos fedora arch rhel alpine rocky alma suse '
        'opensuse kali mint manjaro gentoo nixos',
  ),
  (PhosphorIconsLight.gitBranch, 10, 'git gitea forgejo bitbucket'),
  (PhosphorIconsLight.house, 95, 'home homelab homeassistant hass'),
  (
    PhosphorIconsLight.globe,
    185,
    'web www nginx apache http https site caddy wordpress',
  ),
  (
    PhosphorIconsLight.cloud,
    195,
    'aws ec2 gcp azure cloud vps droplet digitalocean linode hetzner vultr '
        'lightsail',
  ),
  (PhosphorIconsLight.flask, 170, 'ci jenkins runner build test staging qa'),
  (PhosphorIconsLight.code, 230, 'dev devbox development code'),
];

/// Keyword to its index in [_kinds].
final Map<String, int> _kindOf = {
  for (var i = _kinds.length - 1; i >= 0; i--)
    for (final word in _kinds[i].$3.split(' ')) word: i,
};

final RegExp _separator = RegExp(r'[^a-z0-9]+');
final RegExp _trailingDigits = RegExp(r'\d+$');

Iterable<String> _words(String text) => text
    .toLowerCase()
    .split(_separator)
    .map((word) => word.replaceFirst(_trailingDigits, ''))
    .where((word) => word.isNotEmpty);

/// Picks the avatar for a host. The name is searched first, then [detail]
/// (`user@host:port`) and then the group. Only the user and the first label
/// of the host count from the address: a `pi` or `git` user, or `db1` in
/// `db1.internal`, says something, while domains like `.test`, `.dev` or
/// `.ai` do not.
SshHostGlyph sshHostGlyph(
  String name, {
  String detail = '',
  String group = '',
}) {
  final [user, address] = detail.contains('@')
      ? detail.split('@').take(2).toList()
      : ['', detail];
  final hostLabel = address.split(RegExp(r'[.:]')).first;
  for (final source in [name, '$user $hostLabel', group]) {
    int? best;
    for (final word in _words(source)) {
      final kind = _kindOf[word];
      if (kind != null && (best == null || kind < best)) best = kind;
    }
    if (best != null) {
      final (icon, hue, _) = _kinds[best];
      return (icon: icon, initials: '', hue: hue);
    }
  }
  final letters = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(2)
      .map((word) => String.fromCharCode(word.runes.first).toUpperCase())
      .join();
  // FNV-1a keeps the colour stable across runs, unlike String.hashCode.
  var hash = 0x811c9dc5;
  for (final unit in name.toLowerCase().codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return (
    icon: null,
    initials: letters.isEmpty ? '?' : letters,
    hue: (hash % 12) * 30.0,
  );
}

/// Tinted square that tells hosts apart at a glance.
class SshHostAvatar extends StatelessWidget {
  const SshHostAvatar({
    super.key,
    required this.name,
    this.detail = '',
    this.group = '',
    this.size = CbSizes.controlMd,
    this.loading = false,
  });

  final String name, detail, group;
  final double size;

  /// Replaces the glyph with a spinner while a connection is opening.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final glyph = sshHostGlyph(name, detail: detail, group: group);
    final isDark = context.cb.isDark;
    final ink = HSLColor.fromAHSL(
      1,
      glyph.hue,
      0.6,
      isDark ? 0.7 : 0.42,
    ).toColor();
    final Widget content;
    if (loading) {
      content = SizedBox.square(
        dimension: size * 0.5,
        child: CircularProgressIndicator(strokeWidth: 2, color: ink),
      );
    } else if (glyph.icon != null) {
      content = Icon(glyph.icon, size: size * 0.55, color: ink);
    } else {
      content = Text(
        glyph.initials,
        style: CbTypography.label.copyWith(
          color: ink,
          fontSize: size * (glyph.initials.length > 1 ? 0.36 : 0.44),
          height: 1,
          fontWeight: CbTypography.semibold,
        ),
      );
    }
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ink.withValues(alpha: isDark ? 0.2 : 0.13),
          borderRadius: size >= CbSizes.controlSm
              ? CbRadii.smAll
              : CbRadii.all(CbRadii.xs),
        ),
        child: SizedBox.square(
          dimension: size,
          child: Center(child: content),
        ),
      ),
    );
  }
}
