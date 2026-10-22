// Builds rust/ with cargo and bundles it as the `cb_native` code asset.
//
// The library is optional: when cargo, the Rust target or the build itself is
// missing, the hook prints a warning and emits no asset. The Dart side then
// reports `CbNative.isAvailable == false` and callers keep their Dart
// implementation, so a machine without Rust still builds and runs the app.
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

const _assetName = 'cb_native';
const _crateName = 'cb_native';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;

    final crateDir = input.packageRoot.resolve('rust/');
    output.dependencies.addAll(_crateInputs(crateDir));

    final triple = _rustTriple(code);
    if (triple == null) {
      _warn(
        'no Rust target for ${code.targetOS}/${code.targetArchitecture}; '
        'using the Dart fallback.',
      );
      return;
    }

    final cargo = _findCargo();
    if (cargo == null) {
      _warn('cargo not found (install rustup); using the Dart fallback.');
      return;
    }

    final targetDir = input.outputDirectoryShared.resolve('cargo-target/');
    final environment = <String, String>{..._linkerEnvironment(code, triple)};

    final result = await Process.run(cargo, [
      'build',
      '--release',
      '--locked',
      '--target',
      triple,
      '--manifest-path',
      crateDir.resolve('Cargo.toml').toFilePath(),
      '--target-dir',
      targetDir.toFilePath(),
    ], environment: environment);
    if (result.exitCode != 0) {
      _warn(
        'cargo build for $triple failed (exit ${result.exitCode}); using the '
        'Dart fallback. If the target is missing, run '
        '`rustup target add $triple`.\n${result.stderr}',
      );
      return;
    }

    final library = File.fromUri(
      targetDir.resolve(
        '$triple/release/${code.targetOS.dylibFileName(_crateName)}',
      ),
    );
    if (!library.existsSync()) {
      _warn('cargo succeeded but ${library.path} is missing.');
      return;
    }

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: _assetName,
        linkMode: DynamicLoadingBundled(),
        file: library.uri,
      ),
    );
  });
}

void _warn(String message) => print('cb_native: $message');

List<Uri> _crateInputs(Uri crateDir) {
  final inputs = <Uri>[
    crateDir.resolve('Cargo.toml'),
    crateDir.resolve('Cargo.lock'),
  ];
  final src = Directory.fromUri(crateDir.resolve('src/'));
  if (src.existsSync()) {
    for (final entity in src.listSync(recursive: true)) {
      if (entity is File) inputs.add(entity.uri);
    }
  }
  return inputs;
}

String? _findCargo() {
  final exe = Platform.isWindows ? 'cargo.exe' : 'cargo';
  final pathSeparator = Platform.isWindows ? ';' : ':';
  final candidates = <String>[
    ...?Platform.environment['PATH']?.split(pathSeparator),
    // Hooks run with a filtered environment; rustup's default location is
    // still reachable through HOME / USERPROFILE.
    for (final home in [
      Platform.environment['USERPROFILE'],
      Platform.environment['HOME'],
    ])
      if (home != null && home.isNotEmpty)
        '$home${Platform.pathSeparator}.cargo${Platform.pathSeparator}bin',
  ];
  for (final dir in candidates) {
    if (dir.isEmpty) continue;
    final file = File('$dir${Platform.pathSeparator}$exe');
    if (file.existsSync()) return file.path;
  }
  return null;
}

String? _rustTriple(CodeConfig code) {
  final arch = code.targetArchitecture;
  switch (code.targetOS) {
    case OS.windows:
      return switch (arch) {
        Architecture.x64 => 'x86_64-pc-windows-msvc',
        Architecture.arm64 => 'aarch64-pc-windows-msvc',
        _ => null,
      };
    case OS.linux:
      return switch (arch) {
        Architecture.x64 => 'x86_64-unknown-linux-gnu',
        Architecture.arm64 => 'aarch64-unknown-linux-gnu',
        _ => null,
      };
    case OS.macOS:
      return switch (arch) {
        Architecture.x64 => 'x86_64-apple-darwin',
        Architecture.arm64 => 'aarch64-apple-darwin',
        _ => null,
      };
    case OS.android:
      return switch (arch) {
        Architecture.arm64 => 'aarch64-linux-android',
        Architecture.arm => 'armv7-linux-androideabi',
        Architecture.x64 => 'x86_64-linux-android',
        Architecture.ia32 => 'i686-linux-android',
        _ => null,
      };
    case OS.iOS:
      final simulator = code.iOS.targetSdk == IOSSdk.iPhoneSimulator;
      return switch (arch) {
        Architecture.arm64 =>
          simulator ? 'aarch64-apple-ios-sim' : 'aarch64-apple-ios',
        Architecture.x64 => 'x86_64-apple-ios',
        _ => null,
      };
  }
  return null;
}

/// Points cargo at the toolchain Flutter already chose: the NDK clang for
/// Android, and an @rpath install name on Apple so the bundled dylib loads.
Map<String, String> _linkerEnvironment(CodeConfig code, String triple) {
  final envTriple = triple.toUpperCase().replaceAll('-', '_');
  switch (code.targetOS) {
    case OS.android:
      final compiler = code.cCompiler?.compiler;
      if (compiler == null) return const {};
      // Native Assets bypasses Gradle's CMake settings. Keep cb_native's ELF
      // LOAD segments compatible with Android 16 KB pages on every NDK.
      final clangTarget = triple == 'armv7-linux-androideabi'
          ? 'armv7a-linux-androideabi'
          : triple;
      return {
        'CARGO_TARGET_${envTriple}_LINKER': compiler.toFilePath(),
        'CARGO_TARGET_${envTriple}_RUSTFLAGS':
            '-C link-arg=--target=$clangTarget${code.android.targetNdkApi} '
            '-C link-arg=-Wl,-z,max-page-size=16384 '
            '-C link-arg=-Wl,-z,common-page-size=16384',
      };
    case OS.macOS:
    case OS.iOS:
      return {
        'CARGO_TARGET_${envTriple}_RUSTFLAGS':
            '-C link-arg=-Wl,-install_name,@rpath/'
            '${code.targetOS.dylibFileName(_crateName)} '
            '-C link-arg=-Wl,-headerpad_max_install_names',
      };
    default:
      return const {};
  }
}
