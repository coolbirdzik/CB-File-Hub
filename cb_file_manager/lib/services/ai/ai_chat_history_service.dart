import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../models/ai/ai_conversation.dart';
import '../../models/ai/ai_message.dart';
import '../../utils/app_logger.dart';

/// Persists and loads multiple AI chat conversations using SharedPreferences.
///
/// Storage layout:
///   `ai_conv_index`  → JSON list of [AiConversationSummary] (no message bodies)
///   `ai_conv_{id}`   → JSON list of [AiMessage] for that conversation
///
/// Legacy key `ai_chat_history` is migrated automatically on first load.
class AiChatHistoryService {
  static const _indexKey = 'ai_conv_index';
  static const _convPrefix = 'ai_conv_';
  static const _legacyKey = 'ai_chat_history';

  /// Maximum messages kept per conversation (oldest dropped when exceeded).
  static const _maxMessages = 200;

  static const _uuid = Uuid();

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Loads all conversation summaries sorted by most-recently-updated first.
  Future<List<AiConversationSummary>> loadAllSummaries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await _migrateLegacy(prefs);
      final summaries = await _loadIndex(prefs);
      summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return summaries;
    } catch (e) {
      AppLogger.warning('[AiChatHistoryService] Failed to load summaries: $e');
      return [];
    }
  }

  /// Returns the most recently updated conversation summary for [workspacePath].
  Future<AiConversationSummary?> findLatestSummaryForPath(
      String workspacePath) async {
    final normalizedPath = normalizeWorkspacePath(workspacePath);
    if (normalizedPath.isEmpty) return null;

    final summaries = await loadAllSummaries();
    for (final summary in summaries) {
      if (normalizeWorkspacePath(summary.initialPath) == normalizedPath) {
        return summary;
      }
    }
    return null;
  }

  /// Loads the messages for a specific conversation by [id].
  Future<List<AiMessage>> loadConversation(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('$_convPrefix$id');
      if (jsonStr == null) return [];
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list
          .map((e) => AiMessage.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.warning(
          '[AiChatHistoryService] Failed to load conversation $id: $e');
      return [];
    }
  }

  /// Creates or updates a conversation with the given [id], [title], and [messages].
  ///
  /// Only user/assistant messages that are not loading are persisted.
  /// The list is capped at [_maxMessages].
  /// [initialPath] is the directory the user was browsing when the conversation started.
  Future<void> saveConversation(
      String id, String title, List<AiMessage> messages,
      {String initialPath = ''}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Persist messages
      final toSave = messages
          .where((m) =>
              (m.role == AiMessageRole.user ||
                  m.role == AiMessageRole.assistant) &&
              !m.isLoading)
          .toList();
      final capped = toSave.length > _maxMessages
          ? toSave.sublist(toSave.length - _maxMessages)
          : toSave;
      await prefs.setString(
        '$_convPrefix$id',
        jsonEncode(capped.map((m) => m.toJson()).toList()),
      );

      // Update the index entry
      final summaries = await _loadIndex(prefs);
      final idx = summaries.indexWhere((s) => s.id == id);
      final now = DateTime.now();
      final normalizedPath = normalizeWorkspacePath(initialPath);
      if (idx >= 0) {
        summaries[idx] = summaries[idx].copyWith(
          title: title,
          updatedAt: now,
          initialPath: normalizedPath.isNotEmpty
              ? normalizedPath
              : summaries[idx].initialPath,
        );
      } else {
        summaries.insert(
          0,
          AiConversationSummary(
            id: id,
            title: title,
            createdAt: now,
            updatedAt: now,
            initialPath: normalizedPath,
          ),
        );
      }
      await _saveIndex(prefs, summaries);
    } catch (e) {
      AppLogger.warning(
          '[AiChatHistoryService] Failed to save conversation $id: $e');
    }
  }

  /// Deletes a conversation and removes it from the index.
  Future<void> deleteConversation(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_convPrefix$id');
      final summaries = await _loadIndex(prefs);
      summaries.removeWhere((s) => s.id == id);
      await _saveIndex(prefs, summaries);
    } catch (e) {
      AppLogger.warning(
          '[AiChatHistoryService] Failed to delete conversation $id: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<List<AiConversationSummary>> _loadIndex(
      SharedPreferences prefs) async {
    final jsonStr = prefs.getString(_indexKey);
    if (jsonStr == null) return [];
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list
          .map((e) => AiConversationSummary.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveIndex(
      SharedPreferences prefs, List<AiConversationSummary> summaries) async {
    await prefs.setString(
      _indexKey,
      jsonEncode(summaries.map((s) => s.toJson()).toList()),
    );
  }

  /// Migrates the legacy single-conversation key to the multi-conversation
  /// format on first launch after the update.
  Future<void> _migrateLegacy(SharedPreferences prefs) async {
    if (!prefs.containsKey(_legacyKey) || prefs.containsKey(_indexKey)) return;
    try {
      final legacyJson = prefs.getString(_legacyKey);
      if (legacyJson != null) {
        final list = jsonDecode(legacyJson) as List<dynamic>;
        final messages = list
            .map((e) => AiMessage.fromJson(e as Map<String, dynamic>))
            .toList();
        if (messages.isNotEmpty) {
          final firstUser = messages.firstWhere(
            (m) => m.role == AiMessageRole.user,
            orElse: () => messages.first,
          );
          final id = _uuid.v4();
          await saveConversation(
              id, titleFromContent(firstUser.content), messages);
        }
      }
      await prefs.remove(_legacyKey);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Static utilities
  // ---------------------------------------------------------------------------

  /// Derives a short conversation title from the first user message content.
  static String titleFromContent(String content) {
    final trimmed = content.trim();
    return trimmed.length > 60 ? '${trimmed.substring(0, 60)}...' : trimmed;
  }

  /// Normalizes a workspace path for conversation matching.
  static String normalizeWorkspacePath(String path) {
    var normalized = path.trim();
    if (normalized.isEmpty || normalized.startsWith('#')) {
      return '';
    }

    normalized = normalized.replaceAll('/', Platform.pathSeparator);
    if (Platform.isWindows) {
      normalized = normalized.replaceAll('\\', Platform.pathSeparator);
    }

    while (
        normalized.length > 1 && normalized.endsWith(Platform.pathSeparator)) {
      normalized = normalized.substring(
          0, normalized.length - Platform.pathSeparator.length);
    }

    if (Platform.isWindows) {
      normalized = normalized.toLowerCase();
    }

    return normalized;
  }
}
