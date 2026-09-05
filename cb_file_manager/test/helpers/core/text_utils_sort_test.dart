import 'package:cb_file_manager/helpers/core/text_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('A-Z groups Vietnamese and accented Latin tags by base letters', () {
    final tags = ['Zebra', 'Ứng dụng', 'Đồ họa', 'Bản nhạc', 'Ảnh', 'École'];
    tags.sort(TextUtils.compareAlphabetically);
    expect(tags, ['Ảnh', 'Bản nhạc', 'Đồ họa', 'École', 'Ứng dụng', 'Zebra']);
  });

  test('combining Vietnamese accents sort in the same alphabetic group', () {
    final tags = ['Ban', 'A\u0309nh', 'Zebra', 'U\u031b\u0301ng dụng', 'Ảnh'];
    tags.sort(TextUtils.compareAlphabetically);
    expect(tags, ['A\u0309nh', 'Ảnh', 'Ban', 'U\u031b\u0301ng dụng', 'Zebra']);
  });

  test('case and accent ties are deterministic in both directions', () {
    final tags = ['ảnh', 'ANH', 'Anh', 'anh', 'Ảnh'];
    final ascending = tags.toList()..sort(TextUtils.compareAlphabetically);
    final shuffled = tags.reversed.toList()
      ..sort(TextUtils.compareAlphabetically);
    expect(shuffled, ascending);
    expect(ascending, ['ANH', 'Anh', 'anh', 'Ảnh', 'ảnh']);
    tags.sort((a, b) => -TextUtils.compareAlphabetically(a, b));
    expect(tags, ascending.reversed.toList());
  });

  test('sorting preserves empty names, non-Latin scripts and emoji', () {
    final tags = ['日本語', '😀', '', 'Русский', 'Zebra', 'Ảnh'];
    final original = tags.toSet();
    tags.sort(TextUtils.compareAlphabetically);
    expect(tags, ['', 'Ảnh', 'Zebra', 'Русский', '日本語', '😀']);
    expect(tags.toSet(), original);
  });
}
