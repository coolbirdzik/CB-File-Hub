import 'package:cb_file_manager/helpers/core/text_utils.dart';
import 'package:cb_native/cb_native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The recursive search runs in Rust when package:cb_native is built, and in
/// Dart otherwise. A file must match the same queries either way, so the Rust
/// port of `TextUtils.searchKey` has to agree with the Dart one.
void main() {
  final skip = CbNative.isAvailable ? null : 'Rust library not built';

  test('native searchKey matches Dart for every BMP code point', () {
    final mismatches = <String>[];
    for (var unit = 0x20; unit <= 0xFFFF; unit++) {
      if (unit >= 0xD800 && unit <= 0xDFFF) continue;
      final value = 'a${String.fromCharCode(unit)}b';
      final expected = TextUtils.searchKey(value);
      final actual = CbNative.searchKey(value);
      if (actual != expected) {
        mismatches.add(
          'U+${unit.toRadixString(16).padLeft(4, '0')}: '
          'dart="$expected" native="$actual"',
        );
      }
    }
    expect(mismatches, isEmpty, reason: mismatches.take(40).join('\n'));
  }, skip: skip);

  test('native searchKey matches Dart for real file names', () {
    const names = [
      'Bổ Não_(final).MP4',
      'cha\u0300o  ba\u0323n',
      'ĐƯỜNG ĐI - Phần 2 [1080p].mkv',
      '  über.café  ',
      'Ǆungla ǅ ǆ',
      'ﬁle ﬂow Æon œuvre ß',
      'İstanbul ΣΟΦΟΣ',
      'tab\tnew\nline\u00a0nbsp\u3000ideo',
      '日本語ファイル.txt',
      '😀 emoji 👍🏽.png',
      '',
      '...',
    ];
    for (final name in names) {
      expect(CbNative.searchKey(name), TextUtils.searchKey(name), reason: name);
    }
  }, skip: skip);

  test('searchWords is what matchesSearch requires', () {
    expect(TextUtils.searchWords('  Bổ   Não '), ['bo', 'nao']);
    expect(TextUtils.searchWords(' _-. '), isEmpty);
    expect(TextUtils.matchesSearch('anything', ' _-. '), isTrue);
  });
}
