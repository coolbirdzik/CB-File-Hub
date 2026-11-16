# CB File Hub patches

Based on pub.dev `flutter_edge_ai_litertlm` 1.17.0 from
https://github.com/DenisovAV/flutter_edge_ai/tree/main/packages/flutter_edge_ai_litertlm.
Upstream LICENSE and NOTICES are preserved. The native binaries are not vendored:
the original hook still fetches its pinned, SHA-256 verified release artifacts.

- Removed `resolution: workspace` for use as a local dependency override.
- Windows companions use their PE-import filenames (`lib`-prefixed for LiteRT,
  constraints and samplers; `webgpu_dawn.dll` without the prefix for Dawn),
  with upstream Native Assets IDs unchanged. Duplicate extra registrations
  are skipped. Explicit Dart library opens use the same canonical mapping.
- Intel NPU's OpenVINO/TBB stack is opt-in via
  `hooks.user_defines.flutter_edge_ai_litertlm.intel_npu: true` in the app's
  pubspec. CPU/GPU files are unaffected. The upstream runtime availability
  gate reads the native-asset manifest, so an omitted stack is unavailable.

Keep these patches when updating upstream; validate both PE dependency loads
and Native Assets mappings before removing the local override.
