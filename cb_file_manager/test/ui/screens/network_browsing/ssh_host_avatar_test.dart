import 'package:cb_file_manager/ui/screens/ssh/ssh_host_avatar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

void main() {
  test('host kind comes from whole words of the name, ignoring numbers', () {
    expect(sshHostGlyph('Raspberry Pi').icon, PhosphorIconsLight.cpu);
    expect(sshHostGlyph('web01').icon, PhosphorIconsLight.globe);
    expect(sshHostGlyph('db2-replica').icon, PhosphorIconsLight.database);
    expect(sshHostGlyph('Ubuntu box').icon, PhosphorIconsLight.linuxLogo);
    // `pi` inside a longer word is not a Raspberry Pi.
    expect(sshHostGlyph('payment api').icon, isNull);
  });

  test('domains in the address do not decide the kind', () {
    final billing = sshHostGlyph(
      'Acme billing',
      detail: 'svc@billing.acme.test:22',
    );
    expect(billing.icon, isNull);
    expect(billing.initials, 'AB');
    expect(
      sshHostGlyph('Box', detail: 'app@db1.internal:22').icon,
      PhosphorIconsLight.database,
    );
  });

  test('a platform beats a generic word', () {
    expect(sshHostGlyph('Windows build').icon, PhosphorIconsLight.windowsLogo);
    expect(sshHostGlyph('Ubuntu VPS').icon, PhosphorIconsLight.linuxLogo);
  });

  test('a service beats the operating system it runs on', () {
    expect(sshHostGlyph('ubuntu postgres').icon, PhosphorIconsLight.database);
    expect(sshHostGlyph('postgres ubuntu').icon, PhosphorIconsLight.database);
  });

  test('the address and group are fallbacks after the name', () {
    expect(
      sshHostGlyph('Box', detail: 'pi@192.168.1.40:22').icon,
      PhosphorIconsLight.cpu,
    );
    expect(
      sshHostGlyph('Box', group: 'Home lab').icon,
      PhosphorIconsLight.house,
    );
    expect(sshHostGlyph('Box', group: 'Ops').icon, isNull);
    expect(
      sshHostGlyph('Box', group: 'homelab').icon,
      PhosphorIconsLight.house,
    );
    expect(
      sshHostGlyph('nginx', detail: 'git@forge:22').icon,
      PhosphorIconsLight.globe,
    );
  });

  test('unrecognised names get initials and a stable colour', () {
    final production = sshHostGlyph('Production', detail: 'root@10.0.0.12:22');
    expect(production.icon, isNull);
    expect(production.initials, 'P');
    expect(sshHostGlyph('acme billing').initials, 'AB');
    expect(sshHostGlyph('  ').initials, '?');
    expect(sshHostGlyph('Production').hue, production.hue);
    expect(sshHostGlyph('PRODUCTION').hue, production.hue);
  });
}
