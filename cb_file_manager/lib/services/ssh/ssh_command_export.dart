import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'ssh_profile_store.dart';

/// A single pasted command which needs only the platform shell and OpenSSH.
/// The key payload is a secret even though it is encoded as base64.
String buildSshCommand(
  SshProfile profile, {
  SshStoredKey? key,
  TargetPlatform? platform,
}) {
  final target = platform ?? defaultTargetPlatform;
  String quote(String value) => quoteSshShellArgument(value, platform: target);
  final destination =
      '-p ${profile.port} -l ${quote(profile.username)} -- ${quote(profile.host)}';
  if (profile.keyId == null) return 'ssh $destination';
  if (key == null || key.id != profile.keyId || key.pem.trim().isEmpty) {
    throw StateError('SSH key no longer exists.');
  }
  final pem = '${key.pem.trimRight().replaceAll('\r\n', '\n')}\n';
  final payload = base64Encode(utf8.encode(pem));
  if (target == TargetPlatform.windows) {
    // Restrict the empty directory before writing the secret. Inherited ACLs
    // on arbitrary TEMP directories otherwise make OpenSSH reject the key.
    return <String>[
      r"& { $ErrorActionPreference = 'Stop';",
      r"$cbSshDir = Join-Path ([IO.Path]::GetTempPath()) ('cb-ssh-' + [guid]::NewGuid().ToString('N'));",
      r"$cbSshKey = Join-Path $cbSshDir 'identity';",
      'try {',
      r'$null = New-Item -ItemType Directory -Path $cbSshDir;',
      r'$cbSshSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value;',
      r"icacls $cbSshDir /inheritance:r /grant:r ('*' + $cbSshSid + ':(OI)(CI)F') | Out-Null;",
      r"if ($LASTEXITCODE -ne 0) { throw 'Cannot restrict SSH key permissions.' };",
      "[IO.File]::WriteAllBytes(\$cbSshKey, [Convert]::FromBase64String('$payload'));",
      '& ssh -F NUL -o IdentitiesOnly=yes -i \$cbSshKey $destination;',
      '} finally {',
      r'if (Test-Path -LiteralPath $cbSshKey) { Remove-Item -LiteralPath $cbSshKey -Force -ErrorAction Continue };',
      r'if (Test-Path -LiteralPath $cbSshDir) { Remove-Item -LiteralPath $cbSshDir -Force -ErrorAction Continue };',
      '} }',
    ].join(' ');
  }
  final decode = target == TargetPlatform.macOS ? '-D' : '-d';
  return <String>[
    '( umask 077',
    r'cb_ssh_dir=$(mktemp -d) || exit 1',
    r'''trap 'rm -f "$cb_ssh_dir/identity"; rmdir "$cb_ssh_dir"' EXIT''',
    '''printf '%s' '$payload' | base64 $decode > "\$cb_ssh_dir/identity" || exit 1''',
    'ssh -F /dev/null -o IdentitiesOnly=yes -i "\$cb_ssh_dir/identity" $destination',
    ')',
  ].join('; ').replaceAll('; )', ' )');
}
