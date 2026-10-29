import 'dart:convert';
import 'dart:typed_data';

import 'package:cb_file_manager/services/ssh/ssh_profile_store.dart';
import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart' as pc;

List<int> string(List<int> bytes) => [
  0,
  0,
  bytes.length >> 8,
  bytes.length & 255,
  ...bytes,
];

String ppk(OpenSSHEd25519KeyPair key, int version, String password) {
  const comment = 'fixture with trailing space ';
  final encryption = password.isEmpty ? 'none' : 'aes256-cbc';
  final public = key.toPublicKey().encode();
  var private = Uint8List.fromList(string(key.privateKey.sublist(0, 32)));
  final plainPassword = utf8.encode(password);
  Uint8List macKey, aesKey = Uint8List(32), iv = Uint8List(16);
  if (version == 2) {
    macKey = Uint8List.fromList(
      sha1.convert([
        ...utf8.encode('putty-private-key-file-mac-key'),
        ...plainPassword,
      ]).bytes,
    );
    aesKey = Uint8List.fromList(
      [
        for (var i = 0; i < 2; i++)
          ...sha1.convert([0, 0, 0, i, ...plainPassword]).bytes,
      ].take(32).toList(),
    );
  } else if (password.isEmpty) {
    macKey = Uint8List(0);
  } else {
    final derivator = pc.Argon2BytesGenerator()
      ..init(
        pc.Argon2Parameters(
          2,
          Uint8List.fromList(List.generate(16, (i) => i)),
          desiredKeyLength: 80,
          memory: 32,
          iterations: 1,
          lanes: 1,
        ),
      );
    final material = derivator.process(Uint8List.fromList(plainPassword));
    aesKey = Uint8List.sublistView(material, 0, 32);
    iv = Uint8List.sublistView(material, 32, 48);
    macKey = Uint8List.sublistView(material, 48);
  }
  if (password.isNotEmpty) {
    private = Uint8List.fromList([
      ...private,
      ...List.filled((16 - private.length % 16) % 16, 0),
    ]);
  }
  final mac = Hmac(version == 2 ? sha1 : sha256, macKey).convert([
    for (final data in [
      utf8.encode('ssh-ed25519'),
      utf8.encode(encryption),
      utf8.encode(comment),
      public,
      private,
    ])
      ...string(data),
  ]);
  if (password.isNotEmpty) {
    final cipher = pc.CBCBlockCipher(pc.AESEngine())
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(aesKey), iv));
    final encrypted = Uint8List(private.length);
    for (var i = 0; i < private.length; i += 16) {
      cipher.processBlock(private, i, encrypted, i);
    }
    private = encrypted;
  }
  return 'PuTTY-User-Key-File-$version: ssh-ed25519\nEncryption: $encryption\nComment: $comment\nPublic-Lines: 1\n${base64Encode(public)}\n${version == 3 && password.isNotEmpty ? 'Key-Derivation: Argon2id\nArgon2-Memory: 32\nArgon2-Passes: 1\nArgon2-Parallelism: 1\nArgon2-Salt: 000102030405060708090a0b0c0d0e0f\n' : ''}Private-Lines: 1\n${base64Encode(private)}\nPrivate-MAC: $mac\n';
}

void main() {
  for (final version in [2, 3]) {
    for (final password in ['', 'fixture-passphrase']) {
      test(
        'PPK v$version encrypted=${password.isNotEmpty} verifies MAC and preserves identity',
        () {
          final original = SshStoredKey.generate('fixture');
          final key =
              SSHKeyPair.fromPem(original.pem).single as OpenSSHEd25519KeyPair;
          final encoded = ppk(key, version, password);
          final imported = SshStoredKey.import('from PPK', encoded, password);
          expect(imported.fingerprint, original.fingerprint);
          expect(SSHKeyPair.fromPem(imported.pem), hasLength(1));
          expect(
            () => SshStoredKey.import(
              'corrupt',
              encoded.replaceFirst('fixture with', 'tampered with'),
              password,
            ),
            throwsFormatException,
          );
          if (password.isNotEmpty) {
            expect(
              () => SshStoredKey.import('wrong', encoded, 'incorrect'),
              throwsA(anything),
            );
          }
        },
      );
    }
  }
}
