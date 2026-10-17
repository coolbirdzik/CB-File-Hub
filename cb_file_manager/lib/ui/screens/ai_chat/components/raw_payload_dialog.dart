import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../bloc/ai_agent/ai_agent_state.dart';
import 'package:cb_file_manager/config/translation_helper.dart';

/// Debug dialog showing the raw API payload last sent to the provider.
///
/// Used by the "View raw payload" button next to the context badge in the
/// AI chat header.
class RawPayloadDialog extends StatelessWidget {
  final AiAgentState state;

  const RawPayloadDialog({super.key, required this.state});

  static Future<void> show(BuildContext context, AiAgentState state) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
          child: RawPayloadDialog(state: state),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payload = state.lastApiPayload;
    final pretty = payload == null
        ? context.tr.aiNoPayload
        : const JsonEncoder.withIndent('  ').convert(payload);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                PhosphorIconsLight.code,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                context.tr.aiRawApiPayload,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(PhosphorIconsLight.copy, size: 18),
                tooltip: context.tr.copyJson,
                onPressed: payload == null
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: pretty));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(context.tr.aiCopiedToClipboard),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
              ),
              IconButton(
                icon: const Icon(PhosphorIconsLight.x, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          if (payload != null) ...[
            const SizedBox(height: 8),
            Text(
              '${payload['providerId']} · ${payload['modelName']} · '
              '${payload['stream'] == true ? context.tr.aiStreaming : context.tr.aiNonStreaming}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.all(10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: SelectableText(
                    pretty,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
