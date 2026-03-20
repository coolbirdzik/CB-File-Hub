import 'package:cb_file_manager/config/theme_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('addressBarFillColor respects brightness', () {
    expect(
      ThemeConfig.addressBarFillColorFor(Brightness.light),
      Colors.black.withValues(alpha: 0.07),
    );
    expect(
      ThemeConfig.addressBarFillColorFor(Brightness.dark),
      Colors.white.withValues(alpha: 0.10),
    );
  });
}
