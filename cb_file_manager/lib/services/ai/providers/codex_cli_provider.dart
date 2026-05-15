import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../models/ai/ai_message.dart';
import '../../../models/ai/ai_provider_model.dart';
import 'ai_provider.dart';

/// OpenAI-backed provider that delegates requests to the local Codex CLI.
///
/// This is used for ChatGPT/Codex OAuth sessions that are already authenticated
/// locally via `codex login`, instead of using a raw OpenAI API key.
class CodexCliProvider extends AiProvider {
  final AiProviderConfig config;

  CodexCliProvider(this.config);

  static String? codexHomePath() {
    final userProfile = Platform.environment['USERPROFILE'];
    final home = Platform.environment['HOME'];
    if (userProfile != null && userProfile.isNotEmpty) {
      return '$userProfile${Platform.pathSeparator}.codex';
    }
    if (home != null && home.isNotEmpty) {
      return '$home${Platform.pathSeparator}.codex';
    }
    return null;
  }

  static String? codexAuthPath() {
    final home = codexHomePath();
    if (home == null) return null;
    return '$home${Platform.pathSeparator}auth.json';
  }

  static String? codexModelsCachePath() {
    final home = codexHomePath();
    if (home == null) return null;
    return '$home${Platform.pathSeparator}models_cache.json';
  }

  static Future<bool> hasOauthCredentials() async {
    final authPath = codexAuthPath();
    if (authPath == null) return false;

    final authFile = File(authPath);
    if (!await authFile.exists()) return false;

    try {
      final decoded =
          jsonDecode(await authFile.readAsString()) as Map<String, dynamic>;
      final authMode = decoded['auth_mode'] as String?;
      final tokens = decoded['tokens'] as Map<String, dynamic>?;
      final accessToken = tokens?['access_token'] as String?;
      return authMode == 'chatgpt' &&
          accessToken != null &&
          accessToken.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<List<String>> readAvailableModels() async {
    final cachePath = codexModelsCachePath();
    if (cachePath == null) {
      return const <String>[];
    }

    final cacheFile = File(cachePath);
    if (!await cacheFile.exists()) {
      return const <String>[];
    }

    try {
      final decoded =
          jsonDecode(await cacheFile.readAsString()) as Map<String, dynamic>;
      final models = decoded['models'] as List<dynamic>? ?? const <dynamic>[];
      final slugs = <String>{};

      for (final model in models) {
        if (model is! Map<String, dynamic>) continue;
        final slug = model['slug'] as String?;
        final visibility = model['visibility'] as String?;
        if (slug == null || slug.trim().isEmpty) continue;
        if (visibility == 'hidden') continue;
        slugs.add(slug);
      }

      final result = slugs.toList()..sort();
      return result;
    } catch (_) {
      return const <String>[];
    }
  }

  @override
  Future<AiChatResponse> chat(
    List<AiMessage> messages, {
    String? systemPrompt,
  }) async {
    final hasCredentials = await hasOauthCredentials();
    if (!hasCredentials) {
      throw const AiProviderException(
        message:
            'Codex OAuth credentials were not found. Run "codex login" first.',
        type: AiProviderErrorType.auth,
      );
    }

    final prompt = _buildPrompt(messages, systemPrompt: systemPrompt);
    final tempDir = await Directory.systemTemp.createTemp('cb_codex_cli_');
    final outputFile = File(
      '${tempDir.path}${Platform.pathSeparator}last_message.txt',
    );

    try {
      final process = await Process.start(
        'codex',
        [
          'exec',
          '--skip-git-repo-check',
          '--ephemeral',
          '--color',
          'never',
          '--sandbox',
          'read-only',
          '-c',
          'approval_policy="never"',
          '-m',
          config.modelName,
          '-o',
          outputFile.path,
          '-',
        ],
        runInShell: true,
      );

      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      process.stdin.write(prompt);
      await process.stdin.close();

      final exitCode = await process.exitCode.timeout(
        Duration(seconds: config.timeoutSeconds),
        onTimeout: () {
          process.kill();
          throw const AiProviderException(
            message: 'Codex CLI request timed out.',
            type: AiProviderErrorType.network,
          );
        },
      );

      final result = ProcessResult(
        process.pid,
        exitCode,
        await stdoutFuture,
        await stderrFuture,
      );

      if (result.exitCode != 0) {
        final errorText = _extractProcessError(result);
        throw AiProviderException(
          message: errorText,
          type: _classifyCodexError(errorText),
        );
      }

      if (!await outputFile.exists()) {
        throw const AiProviderException(
          message: 'Codex CLI completed without producing a final response.',
          type: AiProviderErrorType.unknown,
        );
      }

      final content = (await outputFile.readAsString()).trim();
      return AiChatResponse(content: content);
    } on SocketException catch (e) {
      throw AiProviderException(
        message: 'Failed to start Codex CLI: ${e.message}',
        type: AiProviderErrorType.network,
      );
    } on ProcessException catch (e) {
      throw AiProviderException(
        message: 'Failed to start Codex CLI: ${e.message}',
        type: AiProviderErrorType.network,
      );
    } on TimeoutException {
      throw const AiProviderException(
        message: 'Codex CLI request timed out.',
        type: AiProviderErrorType.network,
      );
    } on AiProviderException {
      rethrow;
    } catch (e) {
      throw AiProviderException(
        message: 'Codex CLI request failed: $e',
        type: AiProviderErrorType.unknown,
      );
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  @override
  Stream<String> chatStream(
    List<AiMessage> messages, {
    String? systemPrompt,
  }) {
    throw const AiProviderException(
      message: 'Streaming is not supported for Codex OAuth providers.',
      type: AiProviderErrorType.unknown,
    );
  }

  @override
  Future<bool> testConnection() async {
    if (!await hasOauthCredentials()) {
      return false;
    }

    final models = await readAvailableModels();
    if (models.isEmpty) {
      return false;
    }

    try {
      final response = await chat(
        [
          AiMessage(
            id: 'codex_test',
            role: AiMessageRole.user,
            content: 'Reply with exactly OK',
            timestamp: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        ],
        systemPrompt:
            'You are validating a host application connection. Reply with exactly OK.',
      );
      return response.content.trim() == 'OK';
    } on AiProviderException {
      return false;
    }
  }

  @override
  Future<List<String>> listModels() {
    return readAvailableModels();
  }

  @override
  void dispose() {}

  String _buildPrompt(
    List<AiMessage> messages, {
    String? systemPrompt,
  }) {
    final buffer = StringBuffer();

    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      buffer.writeln(systemPrompt.trim());
      buffer.writeln();
    }

    buffer.writeln('HOST APPLICATION RULES:');
    buffer.writeln(
      '- You are acting as a plain text model inside another application.',
    );
    buffer.writeln(
      '- Do not execute shell commands, inspect files, browse the workspace, or use built-in Codex tools or MCP servers.',
    );
    buffer.writeln(
      '- If you need a host-side tool, emit only the tool_call format described in the system prompt.',
    );
    buffer.writeln(
      '- Preserve the exact tool_call tags and JSON structure when emitting them.',
    );
    buffer.writeln('- Respond only as the assistant to the latest user turn.');
    buffer.writeln();
    buffer.writeln('CONVERSATION:');

    for (final message in messages) {
      late final String role;
      switch (message.role) {
        case AiMessageRole.user:
          role = 'User';
          break;
        case AiMessageRole.assistant:
          role = 'Assistant';
          break;
        case AiMessageRole.system:
          role = 'System';
          break;
        case AiMessageRole.tool:
          role = 'Tool';
          break;
      }
      buffer.writeln('$role:');
      buffer.writeln(message.content);
      buffer.writeln();
    }

    return buffer.toString().trim();
  }

  String _extractProcessError(ProcessResult result) {
    final stdoutText = result.stdout.toString().trim();
    final stderrText = result.stderr.toString().trim();
    final combined = [stderrText, stdoutText]
        .where((part) => part.isNotEmpty)
        .join('\n')
        .trim();
    if (combined.isEmpty) {
      return 'Codex CLI exited with code ${result.exitCode}.';
    }
    return combined;
  }

  AiProviderErrorType _classifyCodexError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('login') ||
        lower.contains('auth') ||
        lower.contains('chatgpt account') ||
        lower.contains(
            'not supported when using codex with a chatgpt account')) {
      return AiProviderErrorType.auth;
    }
    if (lower.contains('timed out')) {
      return AiProviderErrorType.network;
    }
    if (lower.contains('rate limit')) {
      return AiProviderErrorType.rateLimit;
    }
    return AiProviderErrorType.unknown;
  }
}
