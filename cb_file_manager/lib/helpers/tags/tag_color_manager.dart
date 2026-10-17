import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lớp quản lý màu sắc cho các tag
class TagColorManager implements Listenable {
  static const String _prefsKey = 'tag_colors';

  // Singleton instance
  static final TagColorManager instance = TagColorManager._internal();

  // Map lưu trữ màu sắc cho các tag
  Map<String, Color> _tagColors = {};

  // Các màu mặc định cho tag
  static final List<Color> defaultColors = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.purple,
    Colors.orange,
    Colors.teal,
    Colors.pink,
    Colors.amber,
    Colors.indigo,
    Colors.cyan,
    Colors.deepOrange,
    Colors.lightBlue,
    Colors.lightGreen,
    Colors.deepPurple,
    Colors.brown,
  ];

  // Stream controller để thông báo khi có thay đổi màu tag
  final List<Function()> _listeners = [];

  // Private constructor
  TagColorManager._internal();

  // Initialize từ SharedPreferences
  Future<void> initialize() async {
    await _loadFromPrefs();
  }

  // Load dữ liệu màu từ SharedPreferences
  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? colorData = prefs.getString(_prefsKey);
      _tagColors = {};
      if (colorData != null && colorData.isNotEmpty) {
        final Map<String, dynamic> colorMap = jsonDecode(colorData);

        colorMap.forEach((key, value) {
          _tagColors[key] = Color(value);
        });
      }
    } catch (e) {
      debugPrint('Error loading tag colors: $e');
      _tagColors = {};
    }
    _notifyListeners();
  }

  // Lưu dữ liệu màu vào SharedPreferences
  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Chuyển đổi Map<String, Color> thành Map<String, int> để lưu
      final Map<String, int> colorValues = {};
      _tagColors.forEach((key, value) {
        colorValues[key] = value.toARGB32();
      });

      await prefs.setString(_prefsKey, jsonEncode(colorValues));

      // Thông báo cho listeners
      _notifyListeners();
    } catch (e) {
      debugPrint('Error saving tag colors: $e');
    }
  }

  // Thêm listener
  @override
  void addListener(Function() listener) {
    _listeners.add(listener);
  }

  // Xóa listener
  @override
  void removeListener(Function() listener) {
    _listeners.remove(listener);
  }

  // Thông báo cho các listeners
  void _notifyListeners() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  // Lấy màu cho tag
  Color getTagColor(String tag) {
    if (_tagColors.containsKey(tag)) {
      return _tagColors[tag]!;
    }

    // Nếu tag chưa có màu, lấy màu mặc định dựa trên hash
    final int hashCode = tag.hashCode.abs();
    return defaultColors[hashCode % defaultColors.length];
  }

  // Thiết lập màu cho tag
  Future<void> setTagColor(String tag, Color color) async {
    _tagColors[tag] = color;
    await _saveToPrefs();
  }

  // Xóa màu của tag
  Future<void> removeTagColor(String tag) async {
    if (_tagColors.containsKey(tag)) {
      _tagColors.remove(tag);
      await _saveToPrefs();
    }
  }

  // Xóa tất cả màu
  Future<void> clearAllColors() async {
    _tagColors.clear();
    await _saveToPrefs();
  }

  // Lấy tất cả tag có màu tùy chỉnh
  Map<String, Color> getAllTagColors() {
    return Map.from(_tagColors);
  }
}
