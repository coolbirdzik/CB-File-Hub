import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:cb_file_manager/services/album_service.dart';
import 'package:cb_file_manager/services/smart_album_service.dart';
import 'package:path/path.dart' as path;
import '../utils/app_logger.dart';

enum RuleCondition {
  contains,
  startsWith,
  endsWith,
  equals,
  regex,
}

class AlbumAutoRule {
  String id;
  String name;
  int albumId;
  String albumName;
  RuleCondition condition;
  String pattern;
  bool isActive;
  DateTime createdAt;
  DateTime? lastTriggered;
  int matchCount;

  AlbumAutoRule({
    required this.id,
    required this.name,
    required this.albumId,
    required this.albumName,
    required this.condition,
    required this.pattern,
    this.isActive = true,
    required this.createdAt,
    this.lastTriggered,
    this.matchCount = 0,
  });

  factory AlbumAutoRule.fromJson(Map<String, dynamic> json) {
    return AlbumAutoRule(
      id: json['id'],
      name: json['name'],
      albumId: json['albumId'],
      albumName: json['albumName'],
      condition: RuleCondition.values[json['condition']],
      pattern: json['pattern'],
      isActive: json['isActive'] ?? true,
      createdAt: DateTime.parse(json['createdAt']),
      lastTriggered: json['lastTriggered'] != null
          ? DateTime.parse(json['lastTriggered'])
          : null,
      matchCount: json['matchCount'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'albumId': albumId,
      'albumName': albumName,
      'condition': condition.index,
      'pattern': pattern,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'lastTriggered': lastTriggered?.toIso8601String(),
      'matchCount': matchCount,
    };
  }

  bool matches(String filename) {
    if (!isActive) return false;

    final name = path.basenameWithoutExtension(filename).toLowerCase();
    final pattern = this.pattern.toLowerCase();

    switch (condition) {
      case RuleCondition.contains:
        return name.contains(pattern);
      case RuleCondition.startsWith:
        return name.startsWith(pattern);
      case RuleCondition.endsWith:
        return name.endsWith(pattern);
      case RuleCondition.equals:
        return name == pattern;
      case RuleCondition.regex:
        try {
          return RegExp(this.pattern, caseSensitive: false).hasMatch(name);
        } catch (e) {
          return false;
        }
    }
  }

  String get conditionDisplayName {
    switch (condition) {
      case RuleCondition.contains:
        return 'Contains';
      case RuleCondition.startsWith:
        return 'Starts with';
      case RuleCondition.endsWith:
        return 'Ends with';
      case RuleCondition.equals:
        return 'Equals';
      case RuleCondition.regex:
        return 'Regex pattern';
    }
  }
}

class AlbumAutoRuleService {
  static const String _configFileName = 'album_auto_rules.json';
  static AlbumAutoRuleService? _instance;

  static AlbumAutoRuleService get instance {
    _instance ??= AlbumAutoRuleService._();
    return _instance!;
  }

  AlbumAutoRuleService._();

  Future<String> _getConfigFilePath() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    return '${appDocDir.path}/$_configFileName';
  }

  Future<List<AlbumAutoRule>> loadRules() async {
    try {
      final configPath = await _getConfigFilePath();
      final file = File(configPath);

      if (!await file.exists()) {
        return [];
      }

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final rulesJson = json['rules'] as List<dynamic>? ?? [];

      return rulesJson
          .map((ruleJson) => AlbumAutoRule.fromJson(ruleJson))
          .toList();
    } catch (e) {
      AppLogger.error('Error loading auto rules', error: e);
      return [];
    }
  }

  Future<bool> saveRules(List<AlbumAutoRule> rules) async {
    try {
      final configPath = await _getConfigFilePath();
      final file = File(configPath);

      final json = {
        'rules': rules.map((rule) => rule.toJson()).toList(),
        'lastUpdated': DateTime.now().toIso8601String(),
      };

      await file.writeAsString(jsonEncode(json));
      return true;
    } catch (e) {
      AppLogger.error('Error saving auto rules', error: e);
      return false;
    }
  }

  Future<bool> addRule(AlbumAutoRule rule) async {
    final rules = await loadRules();
    rules.add(rule);
    return await saveRules(rules);
  }

  Future<bool> updateRule(AlbumAutoRule updatedRule) async {
    final rules = await loadRules();
    final index = rules.indexWhere((rule) => rule.id == updatedRule.id);
    if (index != -1) {
      rules[index] = updatedRule;
      return await saveRules(rules);
    }
    return false;
  }

  Future<bool> deleteRule(String ruleId) async {
    final rules = await loadRules();
    rules.removeWhere((rule) => rule.id == ruleId);
    return await saveRules(rules);
  }

  Future<List<AlbumAutoRule>> getActiveRules() async {
    final rules = await loadRules();
    return rules.where((rule) => rule.isActive).toList();
  }

  Future<List<int>> getMatchingAlbums(String filePath) async {
    final rules = await getActiveRules();
    final filename = path.basename(filePath);

    List<int> matchingAlbumIds = [];

    for (final rule in rules) {
      if (rule.matches(filename)) {
        matchingAlbumIds.add(rule.albumId);

        // Update rule statistics
        rule.lastTriggered = DateTime.now();
        rule.matchCount++;
        await updateRule(rule);
      }
    }

    return matchingAlbumIds.toSet().toList(); // Remove duplicates
  }

  Future<bool> processFile(String filePath) async {
    try {
      final matchingAlbumIds = await getMatchingAlbums(filePath);

      if (matchingAlbumIds.isNotEmpty) {
        final albumService = AlbumService.instance;

        for (final albumId in matchingAlbumIds) {
          try {
            final isSmart =
                await SmartAlbumService.instance.isSmartAlbum(albumId);
            if (!isSmart) {
              await albumService.addFileToAlbum(albumId, filePath);
            }
          } catch (_) {
            // Fallback: if smart service fails, proceed with add
            await albumService.addFileToAlbum(albumId, filePath);
          }
        }

        return true;
      }

      return false;
    } catch (e) {
      AppLogger.error('Error processing file with auto rules', error: e);
      return false;
    }
  }

  Future<Map<String, dynamic>> processDirectory(String directoryPath) async {
    int processedFiles = 0;
    int addedFiles = 0;
    List<String> errors = [];

    try {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        return {
          'processedFiles': 0,
          'addedFiles': 0,
          'errors': ['Directory does not exist']
        };
      }

      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          final extension = path.extension(entity.path).toLowerCase();
          if (['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp']
              .contains(extension)) {
            processedFiles++;
            try {
              final wasAdded = await processFile(entity.path);
              if (wasAdded) addedFiles++;
            } catch (e) {
              errors.add('Error processing ${entity.path}: $e');
            }
          }
        }
      }
    } catch (e) {
      errors.add('Error processing directory: $e');
    }

    return {
      'processedFiles': processedFiles,
      'addedFiles': addedFiles,
      'errors': errors,
    };
  }
}
