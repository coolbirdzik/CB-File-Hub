import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/services/ssh/ssh_command_export.dart';
import 'package:cb_file_manager/services/ssh/ssh_profile_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SshStoredKey key;
  late SshProfile profile;
  setUp(() {
    key = SshStoredKey.generate('export fixture');
    profile = SshProfile(
      id: 'host',
      name: 'Work',
      host: '2001:db8::1',
      username: "domain\\o'connor",
      port: 2222,
      keyId: key.id,
      password: 'must-not-be-exported',
    );
  });

  test('command is one line with a complete key and no saved password', () {
    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    ]) {
      final command = buildSshCommand(profile, key: key, platform: platform);
      expect(command, isNot(contains('\n')));
      expect(command, contains(base64Encode(utf8.encode(key.pem))));
      expect(command, contains('-i '));
      expect(command, contains('IdentitiesOnly=yes'));
      expect(command, isNot(contains(profile.password)));
      expect(command, isNot(contains('BEGIN OPENSSH PRIVATE KEY')));
    }
  });

  test(
    'missing or mismatched keys fail instead of copying an incomplete command',
    () {
      expect(() => buildSshCommand(profile), throwsStateError);
      expect(
        () => buildSshCommand(profile, key: SshStoredKey.generate('other')),
        throwsStateError,
      );
    },
  );

  for (final shell in ['powershell.exe', 'pwsh.exe']) {
    for (final fail in [false, true]) {
      test(
        '$shell creates a usable private key with strict ACLs and cleans up on ${fail ? 'failure' : 'exit'}',
        () async {
          final command = buildSshCommand(
            profile,
            key: key,
            platform: TargetPlatform.windows,
          );
          final expectedPublic = key.publicKey.split(' ').take(2).join(' ');
          // Replace only the network call. ssh-keygen really reads the generated
          // identity and validates its Windows permissions, without connecting.
          final script = <String>[
            r"$ErrorActionPreference = 'Stop'",
            r'$script:cbTestKey = $null',
            r'function ssh {',
            r"$script:cbTestKey = $args[[Array]::IndexOf($args, '-i') + 1]",
            r'if (!(Test-Path -LiteralPath $script:cbTestKey)) { throw "Key was not created" }',
            'if (\$args[-1] -ne ${quoteSshShellArgument(profile.host, platform: TargetPlatform.windows)}) { throw "Host changed" }',
            'if (\$args[[Array]::IndexOf(\$args, "-l") + 1] -ne ${quoteSshShellArgument(profile.username, platform: TargetPlatform.windows)}) { throw "User changed" }',
            r'$cbTestPublic = & ssh-keygen -y -f $script:cbTestKey',
            r'if ($LASTEXITCODE -ne 0) { throw "OpenSSH rejected the exported identity" }',
            'if ((\$cbTestPublic -split " ")[0..1] -join " " -ne ${quoteSshShellArgument(expectedPublic, platform: TargetPlatform.windows)}) { throw "Wrong identity" }',
            if (fail) 'throw "expected SSH failure"',
            '}',
            'try { $command } catch { ${fail ? 'if (\$_.Exception.Message -ne "expected SSH failure") { throw }' : 'throw'} }',
            r'if (!$script:cbTestKey) { throw "SSH was not called" }',
            r'if (Test-Path -LiteralPath $script:cbTestKey) { throw "Identity left behind" }',
            r'if (Test-Path -LiteralPath (Split-Path $script:cbTestKey)) { throw "Directory left behind" }',
            r'Write-Output "VERIFIED_AND_CLEANED"',
          ].join('\n');
          final result = await Process.run(shell, [
            '-NoProfile',
            '-NonInteractive',
            '-Command',
            script,
          ]).timeout(const Duration(seconds: 30));
          expect(
            result.exitCode,
            0,
            reason: '${result.stdout}\n${result.stderr}',
          );
          expect(result.stdout, contains('VERIFIED_AND_CLEANED'));
        },
        skip:
            !Platform.isWindows ||
            (shell == 'pwsh.exe' &&
                Process.runSync('where.exe', [shell]).exitCode != 0),
      );
    }
  }

  final bash = Platform.isWindows
      ? 'C:/Program Files/Git/bin/bash.exe'
      : '/bin/bash';
  for (final fail in [false, true]) {
    test(
      'POSIX command preserves arguments, restricts key permissions and cleans up on ${fail ? 'failure' : 'exit'}',
      () async {
        final command = buildSshCommand(
          profile,
          key: key,
          platform: Platform.isMacOS
              ? TargetPlatform.macOS
              : TargetPlatform.linux,
        );
        final script =
            '''
ssh() {
  while [ "\$1" != '-i' ]; do shift; done
  cb_test_key=\$2
  shift 2
  [ "\$4" = ${quoteSshShellArgument(profile.username, platform: TargetPlatform.linux)} ] || exit 90
  [ "\$6" = ${quoteSshShellArgument(profile.host, platform: TargetPlatform.linux)} ] || exit 91
  [ -f "\$cb_test_key" ] || exit 92
  [ "\$(cat "\$cb_test_key")" = ${quoteSshShellArgument(key.pem.trimRight(), platform: TargetPlatform.linux)} ] || exit 93
  [ "\$(stat ${Platform.isMacOS ? '-f %Lp' : '-c %a'} "\$cb_test_key")" = 600 ] || exit 94
  printf '%s' "\$cb_test_key" > "\$cb_test_result"
  return ${fail ? 23 : 0}
}
cb_test_result=\$(mktemp) || exit 95
$command
cb_test_status=\$?
[ "\$cb_test_status" = ${fail ? 23 : 0} ] || exit 96
cb_test_key=\$(cat "\$cb_test_result")
rm -f "\$cb_test_result"
[ ! -e "\$cb_test_key" ] || exit 97
[ ! -d "\$(dirname "\$cb_test_key")" ] || exit 98
printf '%s' VERIFIED_AND_CLEANED
''';
        final result = await Process.run(bash, [
          '--noprofile',
          '--norc',
          '-c',
          script,
        ]).timeout(const Duration(seconds: 30));
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(result.stdout, contains('VERIFIED_AND_CLEANED'));
      },
      skip: !File(bash).existsSync(),
    );
  }
}
