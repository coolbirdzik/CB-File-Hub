import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:pointycastle/export.dart' as pc;

/// PPK v2/v3 per PuTTY Appendix C. Verify the MAC before constructing a key.
SSHKeyPair decodePuttyPrivateKey(String text, String? passphrase) {
  final lines = const LineSplitter().convert(text.trim());
  final fields = <String, String>{};
  for (var i = 0; i < lines.length; i++) {
    final colon = lines[i].indexOf(':');
    if (colon < 0) throw const FormatException('PPK header');
    final name = lines[i].substring(0, colon);
    final raw = lines[i].substring(colon + 1);
    final value = name == 'Comment'
        ? (raw.startsWith(' ') ? raw.substring(1) : raw)
        : raw.trim();
    if (name == 'Public-Lines' || name == 'Private-Lines') {
      final count = int.parse(value);
      if (count < 1 || count > 20000 || i + count >= lines.length) {
        throw const FormatException('PPK lines');
      }
      fields[name] = lines.skip(i + 1).take(count).join();
      i += count;
    } else {
      fields[name] = value;
    }
  }
  final version = fields.containsKey('PuTTY-User-Key-File-3') ? 3 : 2;
  final algorithm = fields['PuTTY-User-Key-File-$version'];
  if (algorithm == null) throw const FormatException('PPK version');
  final encryption = fields['Encryption']!, comment = fields['Comment'] ?? '';
  final public = base64Decode(fields['Public-Lines']!);
  var private = base64Decode(fields['Private-Lines']!);
  final password = utf8.encode(encryption == 'none' ? '' : passphrase ?? '');
  Uint8List macKey;
  if (version == 2) {
    macKey = Uint8List.fromList(
      sha1.convert([
        ...utf8.encode('putty-private-key-file-mac-key'),
        ...password,
      ]).bytes,
    );
    if (encryption == 'aes256-cbc') {
      final key = Uint8List.fromList(
        [
          for (var i = 0; i < 2; i++)
            ...sha1.convert([0, 0, 0, i, ...password]).bytes,
        ].take(32).toList(),
      );
      private = _aes(private, key, Uint8List(16));
    } else if (encryption != 'none') {
      throw const FormatException('PPK cipher');
    }
  } else if (encryption == 'none') {
    macKey = Uint8List(0);
  } else if (encryption == 'aes256-cbc') {
    final memory = int.parse(fields['Argon2-Memory']!),
        passes = int.parse(fields['Argon2-Passes']!),
        lanes = int.parse(fields['Argon2-Parallelism']!);
    if (memory < 8 ||
        memory > 131072 ||
        passes < 1 ||
        passes > 100 ||
        lanes < 1 ||
        lanes > 16) {
      throw const FormatException('PPK KDF limits');
    }
    final flavour = switch (fields['Key-Derivation']) {
      'Argon2d' => 0,
      'Argon2i' => 1,
      'Argon2id' => 2,
      _ => throw const FormatException('PPK KDF'),
    };
    final generator = pc.Argon2BytesGenerator()
      ..init(
        pc.Argon2Parameters(
          flavour,
          _hex(fields['Argon2-Salt']!),
          desiredKeyLength: 80,
          memory: memory,
          iterations: passes,
          lanes: lanes,
        ),
      );
    final material = generator.process(Uint8List.fromList(password));
    private = _aes(
      private,
      Uint8List.sublistView(material, 0, 32),
      Uint8List.sublistView(material, 32, 48),
    );
    macKey = Uint8List.sublistView(material, 48);
  } else {
    throw const FormatException('PPK cipher');
  }
  final macData = [
    for (final value in [
      utf8.encode(algorithm),
      utf8.encode(encryption),
      utf8.encode(comment),
      public,
      private,
    ])
      ..._string(value),
  ];
  final calculated = Hmac(
    version == 2 ? sha1 : sha256,
    macKey,
  ).convert(macData).bytes;
  final expected = _hex(fields['Private-MAC']!);
  var difference = calculated.length ^ expected.length;
  for (var i = 0; i < calculated.length && i < expected.length; i++) {
    difference |= calculated[i] ^ expected[i];
  }
  if (difference != 0) throw const FormatException('PPK authentication');
  final pub = _SshBytes(public), priv = _SshBytes(private);
  if (utf8.decode(pub.blob()) != algorithm) {
    throw const FormatException('PPK algorithm');
  }
  final SSHKeyPair pair;
  if (algorithm == 'ssh-rsa') {
    final e = pub.integer(), n = pub.integer();
    final d = priv.integer(),
        p = priv.integer(),
        q = priv.integer(),
        inverse = priv.integer();
    pair = OpenSSHRsaKeyPair(n, e, d, inverse, p, q, comment);
  } else if (algorithm == 'ssh-ed25519') {
    final publicKey = pub.blob(), secret = priv.blob();
    if (publicKey.length != 32 || secret.length != 32) {
      throw const FormatException('PPK Ed25519');
    }
    pair = OpenSSHEd25519KeyPair(
      publicKey,
      Uint8List.fromList([...secret, ...publicKey]),
      comment,
    );
  } else if (algorithm.startsWith('ecdsa-sha2-')) {
    pair = OpenSSHEcdsaKeyPair(
      utf8.decode(pub.blob()),
      pub.blob(),
      priv.integer(),
      comment,
    );
  } else {
    throw const FormatException('PPK key type');
  }
  if (base64Encode(pair.toPublicKey().encode()) != base64Encode(public)) {
    throw const FormatException('PPK public key');
  }
  return pair;
}

Uint8List _aes(Uint8List data, Uint8List key, Uint8List iv) {
  if (data.length % 16 != 0) throw const FormatException('PPK block size');
  final cipher = pc.CBCBlockCipher(pc.AESEngine())
    ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), iv));
  final out = Uint8List(data.length);
  for (var i = 0; i < data.length; i += 16) {
    cipher.processBlock(data, i, out, i);
  }
  return out;
}

Uint8List _hex(String value) {
  if (value.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(value)) {
    throw const FormatException('PPK hex');
  }
  return Uint8List.fromList([
    for (var i = 0; i < value.length; i += 2)
      int.parse(value.substring(i, i + 2), radix: 16),
  ]);
}

List<int> _string(List<int> bytes) => [
  (bytes.length >> 24) & 255,
  (bytes.length >> 16) & 255,
  (bytes.length >> 8) & 255,
  bytes.length & 255,
  ...bytes,
];

class _SshBytes {
  final Uint8List bytes;
  int at = 0;
  _SshBytes(this.bytes);
  Uint8List blob() {
    if (at + 4 > bytes.length) throw const FormatException('PPK truncated');
    final length = ByteData.sublistView(bytes).getUint32(at, Endian.big);
    at += 4;
    if (at + length > bytes.length) {
      throw const FormatException('PPK truncated');
    }
    final result = Uint8List.sublistView(bytes, at, at + length);
    at += length;
    return result;
  }

  BigInt integer() {
    final data = blob();
    return data.isEmpty
        ? BigInt.zero
        : BigInt.parse(
            data.map((v) => v.toRadixString(16).padLeft(2, '0')).join(),
            radix: 16,
          );
  }
}
