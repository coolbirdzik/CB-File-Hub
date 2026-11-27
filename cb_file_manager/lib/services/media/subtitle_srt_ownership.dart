import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Per-output records avoid overwriting another window's ownership map.
class SubtitleSrtOwnership {
  static const prefix = 'ai_subtitles_srt_owner:';

  static String pathKey(String path) {
    final key = p.normalize(p.absolute(path));
    return Platform.isWindows ? key.toLowerCase() : key;
  }

  static Future<void> remember(
    SharedPreferences prefs, {
    required String video,
    required String output,
    required List<int> bytes,
  }) async {
    if (p.extension(output).toLowerCase() != '.srt') return;
    final key = '$prefix${sha256.convert(utf8.encode(pathKey(output)))}';
    await prefs.setString(
      key,
      jsonEncode({
        'source': pathKey(video),
        'output': p.normalize(p.absolute(output)),
        'sha256': sha256.convert(bytes).toString(),
      }),
    );
  }

  static Future<
    Map<
      String,
      ({String source, String output, String hash, String preference})
    >
  >
  read(SharedPreferences prefs) async {
    await prefs.reload();
    final result =
        <
          String,
          ({String source, String output, String hash, String preference})
        >{};
    for (final key in prefs.getKeys().where((key) => key.startsWith(prefix))) {
      try {
        final data = jsonDecode(prefs.getString(key)!);
        if (p.extension(data['output'] as String).toLowerCase() != '.srt' ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(data['sha256'] as String)) {
          continue;
        }
        result[pathKey(data['output'] as String)] = (
          source: data['source'] as String,
          output: data['output'] as String,
          hash: data['sha256'] as String,
          preference: key,
        );
      } catch (_) {
        // Incomplete/unknown records never authorize deleting a file.
      }
    }
    return result;
  }
}
