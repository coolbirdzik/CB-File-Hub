import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' show CREDENTIAL;

/// Only reads Termius's named localKey entries, never enumerates credentials.
Future<List<Uint8List>> readTermiusLocalKeys() async {
  final keys = <Uint8List>[];
  for (final service in [
    'Termius',
    'termius-app',
    'Termius (MAS)',
    'termius',
    'com.termius-dmg.mac',
  ]) {
    try {
      final String? value;
      if (Platform.isWindows) {
        value = _credential('$service/localKey');
      } else {
        final process = await Process.run(
          Platform.isMacOS ? '/usr/bin/security' : 'secret-tool',
          Platform.isMacOS
              ? ['find-generic-password', '-s', service, '-a', 'localKey', '-w']
              : ['lookup', 'service', service, 'account', 'localKey'],
        ).timeout(const Duration(seconds: 15));
        value = process.exitCode == 0 ? '${process.stdout}'.trim() : null;
      }
      if (value != null) {
        final bytes = base64Decode(value.trim());
        if (bytes.length == 32) keys.add(bytes);
      }
    } catch (_) {
      // Missing/locked platform entries are reported by the source scanner.
    }
  }
  return keys;
}

String? _credential(String target) {
  final library = DynamicLibrary.open('advapi32.dll');
  final read = library
      .lookupFunction<
        Int32 Function(
          Pointer<Utf16>,
          Uint32,
          Uint32,
          Pointer<Pointer<CREDENTIAL>>,
        ),
        int Function(Pointer<Utf16>, int, int, Pointer<Pointer<CREDENTIAL>>)
      >('CredReadW');
  final free = library
      .lookupFunction<Void Function(Pointer), void Function(Pointer)>(
        'CredFree',
      );
  final name = target.toNativeUtf16(), result = calloc<Pointer<CREDENTIAL>>();
  try {
    if (read(name, 1, 0, result) == 0) return null;
    try {
      final credential = result.value.ref;
      if (credential.CredentialBlobSize > 4096) return null;
      final blob = credential.CredentialBlob.asTypedList(
        credential.CredentialBlobSize,
      );
      for (final text in [
        utf8.decode(blob, allowMalformed: true),
        if (blob.length.isEven)
          String.fromCharCodes([
            for (var i = 0; i < blob.length; i += 2)
              blob[i] | (blob[i + 1] << 8),
          ]),
      ]) {
        try {
          if (base64Decode(text.trim()).length == 32) return text.trim();
        } catch (_) {
          /* try next encoding */
        }
      }
      return null;
    } finally {
      free(result.value);
    }
  } finally {
    calloc.free(name);
    calloc.free(result);
  }
}

/// Fixed per-user SSH session locations. Handles/allocated buffers are scoped.
List<Map<String, String>> readWindowsSshSessions(String app) {
  if (!Platform.isWindows || !['PuTTY', 'WinSCP'].contains(app)) return [];
  final library = DynamicLibrary.open('advapi32.dll');
  final open = library
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Utf16>, Uint32, Uint32, Pointer<IntPtr>),
        int Function(int, Pointer<Utf16>, int, int, Pointer<IntPtr>)
      >('RegOpenKeyExW');
  final close = library
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('RegCloseKey');
  final enumerate = library
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Uint32,
          Pointer<Utf16>,
          Pointer<Uint32>,
          Pointer,
          Pointer,
          Pointer,
          Pointer,
        ),
        int Function(
          int,
          int,
          Pointer<Utf16>,
          Pointer<Uint32>,
          Pointer,
          Pointer,
          Pointer,
          Pointer,
        )
      >('RegEnumKeyExW');
  final query = library
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Utf16>,
          Pointer,
          Pointer<Uint32>,
          Pointer<Uint8>,
          Pointer<Uint32>,
        ),
        int Function(
          int,
          Pointer<Utf16>,
          Pointer,
          Pointer<Uint32>,
          Pointer<Uint8>,
          Pointer<Uint32>,
        )
      >('RegQueryValueExW');
  final path =
      (app == 'PuTTY'
              ? r'Software\SimonTatham\PuTTY\Sessions'
              : r'Software\Martin Prikryl\WinSCP 2\Sessions')
          .toNativeUtf16();
  final root = calloc<IntPtr>(), child = calloc<IntPtr>();
  final name = calloc<Uint16>(32768).cast<Utf16>(), length = calloc<Uint32>();
  final size = calloc<Uint32>(),
      type = calloc<Uint32>(),
      data = calloc<Uint8>(65536);
  final result = <Map<String, String>>[];
  try {
    // HKEY_CURRENT_USER is a sign-extended predefined handle on Windows x64.
    final status = open(-2147483647, path, 0, 0x20019, root);
    if (status == 2) return [];
    if (status != 0) throw const FileSystemException('registry unavailable');
    try {
      for (var index = 0; index < 2000; index++) {
        length.value = 32768;
        final status = enumerate(
          root.value,
          index,
          name,
          length,
          nullptr,
          nullptr,
          nullptr,
          nullptr,
        );
        if (status == 259) break;
        if (status != 0) {
          throw const FileSystemException('registry enumeration');
        }
        final label = name.toDartString(length: length.value);
        if (open(root.value, name, 0, 0x20019, child) != 0) continue;
        try {
          final values = <String, String>{'name': label};
          for (final field in [
            'HostName',
            'UserName',
            'PortNumber',
            'Protocol',
            'FSProtocol',
            'PublicKeyFile',
            'Password',
            'PasswordPlain',
            'ProxyMethod',
            'ProxyHost',
            'ProxyPort',
            'ProxyUsername',
            'ProxyPassword',
            'ProxyPasswordPlain',
            'Tunnel',
          ]) {
            final valueName = field.toNativeUtf16();
            try {
              size.value = 65536;
              if (query(child.value, valueName, nullptr, type, data, size) !=
                  0) {
                continue;
              }
              if (type.value == 4 && size.value == 4) {
                values[field] = '${data.cast<Uint32>().value}';
              } else if ((type.value == 1 || type.value == 2) &&
                  size.value >= 2 &&
                  size.value <= 65536) {
                values[field] = data.cast<Utf16>().toDartString(
                  length: size.value ~/ 2 - 1,
                );
              }
            } finally {
              calloc.free(valueName);
            }
          }
          result.add(values);
        } finally {
          close(child.value);
        }
      }
    } finally {
      close(root.value);
    }
  } finally {
    for (final allocation in <Pointer>[
      path,
      root,
      child,
      name,
      length,
      size,
      type,
      data,
    ]) {
      calloc.free(allocation);
    }
  }
  return result;
}
